// Слой доступа к Ruby-API генератора.
//
// Здесь нет ни одной предметной вычислительной операции: разбор
// спецификации, роли полей, множители сумм, покрытие и статусы считает
// Ruby. Фронт только отправляет запрос, разбирает конверт ответа и, если
// сервер недоступен, показывает сохранённый ответ из lib/fixtures.

import type { BatchResponse, GenerateResponse, SpecsResponse } from './types'
import { demoBatch, demoGenerate, demoSpecs } from './demo'

// В dev фронт живёт на 3000, а API — на 9292, поэтому нужен абсолютный
// адрес. Собранная статика лежит в public/ Ruby-сервера, то есть на том же
// origin, что и API, — там базой должен быть пустой префикс. Переменная
// окружения перекрывает и то и другое.
const DEFAULT_BASE = process.env.NODE_ENV === 'development' ? 'http://localhost:9292' : ''

export const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? DEFAULT_BASE

/** Лимит тела запроса на сервере (SpecGen::Web::Params::MAX_BODY_BYTES). */
export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024

/** Расширения, которые принимает каталог спецификаций (Batch::EXTENSIONS). */
export const UPLOAD_EXTENSIONS = ['.yaml', '.yml', '.json']

const DEFAULT_TIMEOUT_MS = 20_000
// Пакетный прогон гоняет весь каталог через конвейер: 10-20 секунд — норма.
const BATCH_TIMEOUT_MS = 180_000

/** Ответ вместе с признаком «данные сохранённые, а не с сервера». */
export type Loaded<T> = { data: T; demo: boolean }

/** Ошибка, о которой сервер рассказал сам: конверт `error` с текстом для человека. */
export class ApiError extends Error {
  readonly code: string | null
  readonly file: string | null
  readonly location: string | null
  readonly status: number

  constructor(
    message: string,
    options: { code?: string | null; file?: string | null; location?: string | null; status?: number } = {},
  ) {
    super(message)
    this.name = 'ApiError'
    this.code = options.code ?? null
    this.file = options.file ?? null
    this.location = options.location ?? null
    this.status = options.status ?? 0
  }
}

/** Сервер не ответил: сеть, таймаут или 5xx. Только эта ошибка включает демо-режим. */
class TransportError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'TransportError'
  }
}

type ErrorEnvelope = {
  error?: { code?: string | null; message?: string | null; file?: string | null; location?: string | null }
}

/**
 * Ошибка от сервера, но только если это наш конверт `error`. Ответ без
 * конверта означает, что на этом адресе отвечает не API генератора
 * (например, статику раздаёт обычный веб-сервер), — это повод показать
 * сохранённые данные, а не ругаться кодом HTTP.
 */
function toApiError(payload: unknown, status: number): ApiError | TransportError {
  const body = (payload as ErrorEnvelope | null)?.error
  if (body && typeof body.message === 'string' && body.message.length > 0) {
    return new ApiError(body.message, {
      code: body.code ?? null,
      file: body.file ?? null,
      location: body.location ?? null,
      status,
    })
  }
  return new TransportError(`По этому адресу API генератора не отвечает (код ${status}).`)
}

async function request<T>(
  method: 'GET' | 'POST',
  path: string,
  body?: unknown,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<T> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    let response: Response
    try {
      response = await fetch(`${API_BASE}${path}`, {
        method,
        signal: controller.signal,
        headers: body === undefined ? undefined : { 'content-type': 'application/json' },
        body: body === undefined ? undefined : JSON.stringify(body),
      })
    } catch {
      throw new TransportError(
        controller.signal.aborted
          ? `Сервер не ответил за ${Math.round(timeoutMs / 1000)} с.`
          : 'Не удалось связаться с сервером генератора.',
      )
    }

    if (response.status >= 500) {
      throw new TransportError(`Сервер ответил ошибкой ${response.status}.`)
    }

    let text: string
    try {
      text = await response.text()
    } catch {
      throw new TransportError('Ответ сервера оборвался на середине.')
    }

    let payload: unknown = null
    try {
      payload = text.length > 0 ? JSON.parse(text) : null
    } catch {
      payload = null
    }

    if (!response.ok) throw toApiError(payload, response.status)
    if (payload === null) throw new TransportError('Сервер вернул пустой ответ.')
    return payload as T
  } finally {
    clearTimeout(timer)
  }
}

/** Каталог спецификаций. При недоступном сервере — сохранённый каталог. */
export async function loadSpecs(): Promise<Loaded<SpecsResponse>> {
  try {
    return { data: await request<SpecsResponse>('GET', '/api/specs'), demo: false }
  } catch (error) {
    if (error instanceof TransportError) return { data: demoSpecs, demo: true }
    throw error
  }
}

/**
 * Настройки прогона: сервер принимает их и при генерации из каталога, и при
 * загрузке файла, и при вставке текста (SpecGen::Web::Params). `provider` —
 * имя провайдера (иначе выводится из `info.title`), `locale` — язык
 * сгенерированных документов и предупреждений, `overlay` — текст OpenAPI
 * Overlay 1.0.0.
 */
export type RunOptions = { provider?: string; locale?: 'ru' | 'en'; overlay?: string }

/** Тело POST /api/generate: либо спецификация из каталога, либо загруженный текст. */
export type GenerateBody = RunOptions & ({ spec_id: string } | { filename: string; content: string })

/**
 * Генерация артефактов. Сохранённые ответы есть только для двух
 * спецификаций каталога, поэтому для остальных при недоступном сервере
 * честнее сказать об этом, чем показать чужие данные.
 */
export async function generate(body: GenerateBody): Promise<Loaded<GenerateResponse>> {
  try {
    return { data: await request<GenerateResponse>('POST', '/api/generate', body), demo: false }
  } catch (error) {
    if (!(error instanceof TransportError)) throw error
    const saved = 'spec_id' in body ? demoGenerate(body.spec_id) : null
    if (saved) return { data: saved, demo: true }
    throw new ApiError(
      `${error.message} Сохранённого ответа для этой спецификации нет — запустите сервер командой ` +
        '`ruby bin/serve --port 9292` и повторите.',
      { code: 'demo_unavailable' },
    )
  }
}

/** Пакетный прогон по всему каталогу. Идёт десятки секунд — таймаут длинный. */
export async function loadBatch(): Promise<Loaded<BatchResponse>> {
  try {
    return { data: await request<BatchResponse>('GET', '/api/batch', undefined, BATCH_TIMEOUT_MS), demo: false }
  } catch (error) {
    if (error instanceof TransportError) return { data: demoBatch, demo: true }
    throw error
  }
}

/** Проверка живости сервера: нужна, чтобы баннер демо-режима не врал до первого запроса. */
export async function checkHealth(): Promise<boolean> {
  try {
    await request<{ status: string }>('GET', '/api/health', undefined, 5000)
    return true
  } catch {
    return false
  }
}

/** Текст ошибки для человека: сообщение сервера плюс файл и место, если они названы. */
export function describeError(error: unknown): { message: string; where: string | null } {
  if (error instanceof ApiError) {
    const where = [error.file, error.location].filter(Boolean).join(' · ')
    return { message: error.message, where: where.length > 0 ? where : null }
  }
  if (error instanceof Error) return { message: error.message, where: null }
  return { message: 'Неизвестная ошибка.', where: null }
}

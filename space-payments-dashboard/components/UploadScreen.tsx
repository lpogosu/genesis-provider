// Экран загрузки спецификации: перенесён визуальный язык из Stitch
// (screen_upload.html) — заголовок, зона перетаскивания, карточка примера,
// информационные карточки справа. Добавлены вкладка вставки текста, панель
// настроек прогона и фильтр каталога — вся смысловая функциональность,
// стоящая за ними, уже была на сервере, здесь только форма ввода.
'use client'

import { useMemo, useState } from 'react'
import { ChevronDown, ChevronRight, ClipboardPaste, FileJson2, FileText, Lightbulb, Loader2, Settings2, UploadCloud } from 'lucide-react'

import { UPLOAD_EXTENSIONS } from '@/lib/api'
import type { RunOptions } from '@/lib/api'
import type { Spec } from '@/lib/types'

const formatBytes = (bytes: number) =>
  bytes > 100000 ? `${(bytes / 1000).toFixed(0)} КБ` : `${(bytes / 1000).toFixed(1)} КБ`

const FORMAT_LABELS: Record<string, string> = {
  '.yaml': 'YAML (.yaml)',
  '.yml': 'YAML (.yml)',
  '.json': 'JSON (.json)',
}

type SourceTab = 'file' | 'paste'

export function UploadScreen({
  specs,
  loading,
  busy,
  options,
  onOptionsChange,
  onGenerate,
  onPick,
  onDrop,
  onPaste,
}: {
  specs: Spec[]
  loading: boolean
  busy: string | null
  options: RunOptions
  onOptionsChange: (options: RunOptions) => void
  onGenerate: (spec: Spec) => void
  onPick: () => void
  onDrop: (file: File) => void
  onPaste: (content: string, filename: string) => void
}) {
  const [over, setOver] = useState(false)
  const [tab, setTab] = useState<SourceTab>('file')
  const [pasted, setPasted] = useState('')
  const [pasteName, setPasteName] = useState('')
  const [query, setQuery] = useState('')
  const novapay = specs.find((spec) => spec.id === 'novapay')
  const rest = specs.filter((spec) => spec.id !== 'novapay')
  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase()
    if (needle === '') return rest
    return rest.filter(
      (spec) => spec.file.toLowerCase().includes(needle) || spec.title.toLowerCase().includes(needle),
    )
  }, [rest, query])

  return (
    <div className="grid grid-cols-1 gap-8 xl:grid-cols-12 xl:items-start">
      <section className="flex flex-col gap-6 xl:col-span-8">
        <div>
          <h1 className="text-3xl font-extrabold tracking-tight text-slate-900">
            Загрузите спецификацию провайдера
          </h1>
          <p className="mt-2 max-w-2xl text-base leading-relaxed text-slate-500">
            Мы проанализируем OpenAPI и сгенерируем интеграцию: сервис, документацию, фикстуры и отчёт о
            неоднозначностях.
          </p>
        </div>

        <div className="flex items-center gap-1 rounded-xl bg-slate-100 p-1 text-sm font-medium text-slate-600">
          <button
            onClick={() => setTab('file')}
            className={`flex flex-1 items-center justify-center gap-2 rounded-lg py-2 transition-colors ${
              tab === 'file' ? 'bg-white font-semibold text-blue-700 shadow-2xs' : 'hover:text-slate-900'
            }`}
          >
            <UploadCloud className="size-4" strokeWidth={1.8} />
            Загрузить файл
          </button>
          <button
            onClick={() => setTab('paste')}
            className={`flex flex-1 items-center justify-center gap-2 rounded-lg py-2 transition-colors ${
              tab === 'paste' ? 'bg-white font-semibold text-blue-700 shadow-2xs' : 'hover:text-slate-900'
            }`}
          >
            <ClipboardPaste className="size-4" strokeWidth={1.8} />
            Вставить YAML/JSON
          </button>
        </div>

        {tab === 'file' ? (
          <div
            onDragOver={(event) => {
              event.preventDefault()
              setOver(true)
            }}
            onDragLeave={() => setOver(false)}
            onDrop={(event) => {
              event.preventDefault()
              setOver(false)
              const file = event.dataTransfer.files?.[0]
              if (file) onDrop(file)
            }}
            className={`flex flex-col items-center justify-center space-y-4 rounded-2xl border-2 border-dashed p-12 text-center transition-colors ${
              over ? 'border-blue-400 bg-blue-50/40' : 'border-blue-200 bg-blue-50/20 hover:border-blue-300'
            }`}
          >
            <div className="flex size-16 items-center justify-center rounded-2xl border border-blue-100 bg-white text-blue-600 shadow-xs">
              <UploadCloud className="size-8" strokeWidth={1.8} />
            </div>
            <div className="space-y-1">
              <p className="text-base font-semibold text-slate-800">
                Перетащите файл сюда или{' '}
                <button onClick={onPick} className="text-blue-600 hover:underline">
                  выберите на компьютере
                </button>
              </p>
              <p className="text-sm text-slate-400">
                Поддерживаются файлы в формате YAML или JSON (OpenAPI 3.0+), до 5 МБ
              </p>
            </div>
            <div className="pt-2">
              <button
                onClick={onPick}
                disabled={busy !== null}
                className="rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-medium text-white shadow-sm shadow-blue-500/20 transition hover:bg-blue-700 active:bg-blue-800 disabled:opacity-50"
              >
                Выбрать файл
              </button>
            </div>
          </div>
        ) : (
          <div className="space-y-3 rounded-2xl border border-slate-200/90 bg-white p-5 shadow-2xs">
            <textarea
              value={pasted}
              onChange={(event) => setPasted(event.target.value)}
              placeholder="Вставьте содержимое OpenAPI-спецификации (YAML или JSON)…"
              spellCheck={false}
              className="h-56 w-full resize-y rounded-xl border border-slate-200 bg-slate-50/60 p-3 font-mono text-xs text-slate-800 outline-none focus:border-blue-300 focus:bg-white"
            />
            <div className="flex items-center gap-3">
              <input
                value={pasteName}
                onChange={(event) => setPasteName(event.target.value)}
                placeholder="имя файла (необязательно), например provider.yaml"
                className="min-w-0 flex-1 rounded-lg border border-slate-200 px-3 py-2 text-xs text-slate-700 outline-none focus:border-blue-300"
              />
              <button
                onClick={() => onPaste(pasted, pasteName)}
                disabled={busy !== null || pasted.trim().length === 0}
                className="shrink-0 rounded-xl bg-blue-600 px-5 py-2 text-sm font-medium text-white shadow-sm shadow-blue-500/20 transition hover:bg-blue-700 active:bg-blue-800 disabled:opacity-50"
              >
                {busy !== null ? <Loader2 className="size-4 animate-spin" /> : 'Сгенерировать'}
              </button>
            </div>
          </div>
        )}

        <RunSettings options={options} onChange={onOptionsChange} />

        <div className="space-y-3 pt-2">
          <div>
            <h2 className="text-base font-bold text-slate-900">Попробовать на примере</h2>
            <p className="text-sm text-slate-500">Ознакомьтесь с возможностями сервиса на готовом примере.</p>
          </div>

          {novapay && (
            <button
              onClick={() => onGenerate(novapay)}
              disabled={busy !== null}
              className="group flex w-full items-center justify-between rounded-2xl border border-slate-200/90 bg-white p-4 shadow-2xs transition hover:bg-slate-50/80 disabled:opacity-50"
            >
              <div className="flex items-center gap-3.5">
                <div className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-blue-50 text-blue-600">
                  <FileText className="size-5" strokeWidth={1.8} />
                </div>
                <span className="text-sm font-semibold text-slate-800">Загрузить пример NovaPay</span>
              </div>
              {busy === novapay.file ? (
                <Loader2 className="size-5 animate-spin text-slate-400" />
              ) : (
                <ChevronRight className="size-5 text-slate-400 transition group-hover:translate-x-0.5 group-hover:text-slate-600" />
              )}
            </button>
          )}

          <div className="rounded-2xl border border-slate-200/90 bg-white shadow-2xs">
            <div className="flex items-center justify-between border-b border-slate-100 px-4 py-3">
              <span className="text-xs font-semibold text-slate-700">Каталог спецификаций</span>
              <span className="font-mono text-[10px] text-slate-400">
                {loading ? 'загрузка…' : `${filtered.length} из ${rest.length}`}
              </span>
            </div>
            <div className="border-b border-slate-100 px-4 py-2.5">
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Поиск по имени файла или заголовку…"
                className="w-full rounded-lg border border-slate-200 bg-slate-50/60 px-3 py-1.5 text-xs text-slate-700 outline-none focus:border-blue-300 focus:bg-white"
              />
            </div>
            <div className="divide-y divide-slate-100">
              {loading && <div className="px-4 py-5 text-xs text-slate-400">Читаем каталог спецификаций…</div>}
              {!loading && rest.length === 0 && (
                <div className="px-4 py-5 text-xs text-slate-400">Каталог пуст.</div>
              )}
              {!loading && rest.length > 0 && filtered.length === 0 && (
                <div className="px-4 py-5 text-xs text-slate-400">По запросу «{query}» ничего не нашлось.</div>
              )}
              {filtered.map((spec) => (
                <div key={spec.id} className="flex items-center justify-between gap-4 px-4 py-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="truncate font-mono text-xs text-slate-700">{spec.file}</span>
                      {spec.own && (
                        <span className="rounded bg-blue-50 px-1.5 py-0.5 font-mono text-[9px] uppercase text-blue-600">
                          own
                        </span>
                      )}
                    </div>
                    <div className="mt-0.5 text-xs text-slate-400">
                      {spec.title} · {spec.openapi} · {formatBytes(spec.bytes)}
                    </div>
                  </div>
                  <button
                    onClick={() => onGenerate(spec)}
                    disabled={busy !== null}
                    className="shrink-0 rounded-lg border border-slate-200 px-3 py-1.5 text-xs font-medium text-slate-600 transition hover:border-blue-300 hover:text-blue-600 disabled:opacity-50"
                  >
                    {busy === spec.file ? <Loader2 className="size-3.5 animate-spin" /> : 'Сгенерировать'}
                  </button>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      <aside className="flex flex-col gap-5 xl:col-span-4">
        <div className="rounded-2xl border border-slate-200/90 bg-white p-6 shadow-2xs">
          <h3 className="mb-5 text-base font-bold text-slate-900">Что произойдёт дальше</h3>
          <div className="relative space-y-6">
            <div className="absolute bottom-4 left-4 top-4 w-px bg-slate-200" />
            {[
              ['Анализ спецификации', 'Мы разберём структуры, методы, схемы и особенности провайдера.'],
              ['Генерация интеграции', 'Создадим сервис, документацию, фикстуры и отчёт.'],
              ['Проверка и доработка', 'Вы сможете увидеть неоднозначности и при необходимости добавить Overlay.'],
              ['Готово', 'Скачайте файлы или просмотрите их прямо в интерфейсе.'],
            ].map(([title, text], index) => (
              <div key={title} className="relative z-10 flex items-start gap-4">
                <div className="flex size-8 shrink-0 items-center justify-center rounded-full bg-blue-100 text-xs font-bold text-blue-600 ring-4 ring-white">
                  {index + 1}
                </div>
                <div>
                  <h4 className="text-sm font-bold text-slate-800">{title}</h4>
                  <p className="mt-0.5 text-xs leading-normal text-slate-500">{text}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="rounded-2xl border border-slate-200/90 bg-white p-6 shadow-2xs">
          <h3 className="mb-4 text-base font-bold text-slate-900">Поддерживаемые форматы</h3>
          <ul className="space-y-3">
            {UPLOAD_EXTENSIONS.map((extension) => (
              <li key={extension} className="flex items-center gap-3 text-sm text-slate-700">
                <FileJson2 className="size-4 shrink-0 text-slate-400" strokeWidth={1.8} />
                <span>{FORMAT_LABELS[extension] ?? extension}</span>
              </li>
            ))}
          </ul>
          <p className="mt-4 border-t border-slate-100 pt-4 text-xs leading-relaxed text-slate-500">
            Файл должен быть корректным OpenAPI, содержащим описание API провайдера.
          </p>
        </div>

        <div className="flex items-start gap-3.5 rounded-2xl border border-slate-200/90 bg-white p-5 shadow-2xs">
          <Lightbulb className="mt-0.5 size-5 shrink-0 text-slate-600" strokeWidth={1.8} />
          <p className="text-xs leading-relaxed text-slate-600">
            <strong className="font-bold text-slate-800">Совет:</strong> если в спецификации есть особенности,
            которые не описаны явно, мы покажем их в отчёте и предложим, как их уточнить.
          </p>
        </div>
      </aside>
    </div>
  )
}

/**
 * Настройки прогона: имя провайдера, язык сообщений и текст OpenAPI Overlay.
 * Уходят в тело запроса при любом источнике спецификации — из каталога,
 * из файла или из вставленного текста (см. lib/api.ts, RunOptions).
 */
function RunSettings({ options, onChange }: { options: RunOptions; onChange: (options: RunOptions) => void }) {
  const [open, setOpen] = useState(false)
  const filled = [options.provider, options.locale, options.overlay].filter(Boolean).length

  return (
    <div className="rounded-2xl border border-slate-200/90 bg-white shadow-2xs">
      <button
        onClick={() => setOpen((value) => !value)}
        className="flex w-full items-center justify-between px-5 py-3.5 text-left"
      >
        <div className="flex items-center gap-2.5">
          <Settings2 className="size-4 text-slate-500" strokeWidth={1.8} />
          <span className="text-sm font-bold text-slate-900">Настройки прогона</span>
          {filled > 0 && (
            <span className="rounded-full bg-blue-50 px-2 py-0.5 text-[10px] font-semibold text-blue-600">
              {filled}
            </span>
          )}
        </div>
        {open ? <ChevronDown className="size-4 text-slate-400" /> : <ChevronRight className="size-4 text-slate-400" />}
      </button>
      {open && (
        <div className="space-y-4 border-t border-slate-100 px-5 py-4">
          <div>
            <label className="text-xs font-semibold text-slate-700">Имя провайдера</label>
            <p className="mb-1.5 text-[11px] text-slate-400">Необязательно — иначе выводится из info.title спецификации.</p>
            <input
              value={options.provider ?? ''}
              onChange={(event) => onChange({ ...options, provider: event.target.value || undefined })}
              placeholder="например, novapay"
              className="w-full rounded-lg border border-slate-200 px-3 py-2 text-xs text-slate-700 outline-none focus:border-blue-300"
            />
          </div>
          <div>
            <label className="text-xs font-semibold text-slate-700">Язык сообщений</label>
            <p className="mb-1.5 text-[11px] text-slate-400">Влияет на язык документации и предупреждений.</p>
            <select
              value={options.locale ?? 'ru'}
              onChange={(event) => onChange({ ...options, locale: event.target.value as 'ru' | 'en' })}
              className="w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-xs text-slate-700 outline-none focus:border-blue-300"
            >
              <option value="ru">Русский</option>
              <option value="en">English</option>
            </select>
          </div>
          <div>
            <label className="text-xs font-semibold text-slate-700">OpenAPI Overlay</label>
            <p className="mb-1.5 text-[11px] text-slate-400">Необязательно — текст Overlay 1.0.0 с переопределениями.</p>
            <textarea
              value={options.overlay ?? ''}
              onChange={(event) => onChange({ ...options, overlay: event.target.value || undefined })}
              placeholder={'overlay: 1.0.0\ninfo:\n  title: …\n  version: 1.0.0\nactions: []'}
              spellCheck={false}
              className="h-28 w-full resize-y rounded-lg border border-slate-200 bg-slate-50/60 p-2.5 font-mono text-[11px] text-slate-800 outline-none focus:border-blue-300 focus:bg-white"
            />
          </div>
        </div>
      )}
    </div>
  )
}

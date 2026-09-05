// Демо-режим: настоящие ответы Ruby-API, снятые с работающего сервера и
// сохранённые в lib/fixtures. Это не выдуманные моки — те же байты, что
// отдаёт `ruby bin/serve`. Используются только тогда, когда сервер не
// отвечает, и всегда под баннером.

import batchFixture from './fixtures/batch.json'
import brokenFixture from './fixtures/generate-broken.json'
import novapayFixture from './fixtures/generate-novapay.json'
import specsFixture from './fixtures/specs.json'
import type { BatchResponse, GenerateResponse, SpecsResponse } from './types'

export const demoSpecs = specsFixture as unknown as SpecsResponse
export const demoBatch = batchFixture as unknown as BatchResponse

const SAVED: Record<string, GenerateResponse> = {
  novapay: novapayFixture as unknown as GenerateResponse,
  broken: brokenFixture as unknown as GenerateResponse,
}

/** Сохранённый ответ генерации по имени спецификации, если он есть. */
export function demoGenerate(specId: string): GenerateResponse | null {
  return SAVED[specId] ?? null
}

/** Имена спецификаций, которые демо-режим умеет показать целиком. */
export const DEMO_SPEC_IDS = Object.keys(SAVED)

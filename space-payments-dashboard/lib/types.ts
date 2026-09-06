// Формы ответов Ruby-API. Совпадают байт в байт с тем, что печатает
// SpecGen::Web::Api, — сверено по сохранённым ответам в lib/fixtures.

export type Severity = 'error' | 'warning' | 'info'

export type Spec = {
  id: string
  file: string
  title: string
  openapi: string
  bytes: number
  own: boolean
}

export type SpecsResponse = { specs: Spec[] }

export type Warning = {
  code: string
  severity: Severity
  message: string
  json_path: string | null
  suggested_overlay: string | null
}

export type Artifact = {
  kind: string
  filename: string
  language: string
  lines: number
  bytes: number
  content: string
}

/**
 * Сводка анализа. Поля `auth`, `units` и `base_url` — готовые строки для
 * человека: их печатают как есть, разбирать их на фронте нельзя.
 */
export type Summary = {
  operations: number
  operations_with_role: number
  schemas: number
  fields: number
  coverage_percent: number
  contract_coverage_percent: number
  warnings: { total: number; error: number; warning: number; info: number }
  auth: string
  units: string
  base_url: string | null
  statuses: { total: number; mapped: number }
  events: { total: number; mapped: number }
  webhook: { present: boolean; path: string | null; signature_header: string | null }
  idempotency_header: string | null
}

export type AnalyzeResponse = {
  provider: string
  summary: Summary
  warnings: Warning[]
}

export type GenerateResponse = AnalyzeResponse & { artifacts: Artifact[] }

export type BatchRow = {
  file: string
  provider: string
  operations: number
  operations_with_role: number
  coverage_percent: number
  contract_coverage_percent: number
  warnings: number
  artifacts: number
  error: string | null
}

export type BatchResponse = { total: number; generated: number; rows: BatchRow[] }

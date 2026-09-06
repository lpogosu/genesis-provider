// Экран пакетного прогона: таблица по каталогу спецификаций, светлая тема.
'use client'

import { Loader2, Search } from 'lucide-react'

import type { BatchResponse, BatchRow } from '@/lib/types'

export type SortKey = 'coverage_percent' | 'operations' | 'warnings'

const LABELS: Record<SortKey, string> = {
  coverage_percent: 'покрытие',
  operations: 'операции',
  warnings: 'сигналы',
}

export function BatchScreen({
  batch,
  rows,
  loading,
  elapsed,
  sortKey,
  setSortKey,
}: {
  batch: BatchResponse | null
  rows: BatchRow[]
  loading: boolean
  elapsed: number
  sortKey: SortKey
  setSortKey: (value: SortKey) => void
}) {
  return (
    <div className="space-y-6">
      <div className="flex flex-col justify-between gap-4 md:flex-row md:items-end">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Все провайдеры</h1>
          <p className="mt-2 max-w-xl text-sm leading-relaxed text-slate-500">
            Пакетная сводка по источникам в репозитории: каждый файл прогоняется через весь конвейер целиком.
          </p>
        </div>
        <div className="flex items-center gap-2 text-slate-500">
          <Search className="size-4" />
          <span className="font-mono text-xs">{batch ? `${batch.generated} / ${batch.total} источников` : '—'}</span>
        </div>
      </div>

      {loading && (
        <div className="space-y-3 rounded-xl border border-slate-200 bg-white p-6 shadow-2xs">
          <div className="flex items-center gap-3 text-sm text-slate-700">
            <Loader2 className="size-4 animate-spin text-blue-600" />
            Конвейер идёт по всему каталогу — это занимает 10–20 секунд. Прошло: {elapsed} с.
          </div>
          <div className="h-1 w-full overflow-hidden rounded-full bg-slate-100">
            <div className="h-full w-1/3 animate-pulse rounded-full bg-blue-600" />
          </div>
        </div>
      )}

      {!loading && rows.length === 0 && (
        <div className="rounded-xl border border-dashed border-slate-300 px-6 py-16 text-center text-sm text-slate-400">
          Пакетный прогон ничего не вернул.
        </div>
      )}

      {rows.length > 0 && (
        <>
          <div className="flex gap-2">
            {(Object.keys(LABELS) as SortKey[]).map((key) => (
              <button
                key={key}
                onClick={() => setSortKey(key)}
                className={`rounded-lg border px-3 py-1.5 text-xs font-medium capitalize transition-colors ${
                  sortKey === key
                    ? 'border-blue-300 bg-blue-50 text-blue-700'
                    : 'border-slate-200 text-slate-500 hover:border-slate-300'
                }`}
              >
                {LABELS[key]}
              </button>
            ))}
          </div>
          <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-2xs">
            <table className="w-full min-w-[760px] text-left text-sm">
              <thead>
                <tr className="border-b border-slate-200 bg-slate-50 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
                  <th className="px-4 py-3">Источник</th>
                  <th className="px-3 py-3">Провайдер</th>
                  <th className="px-3 py-3">Опер.</th>
                  <th className="px-3 py-3">Сопост.</th>
                  <th className="px-3 py-3">Покрытие</th>
                  <th className="px-3 py-3">В контракте</th>
                  <th className="px-3 py-3">Сигналы</th>
                  <th className="px-3 py-3">Файлы</th>
                  <th className="px-3 py-3">Статус</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {rows.map((row) => (
                  <tr key={row.file} className="align-top hover:bg-slate-50/70">
                    <td className="px-4 py-3 font-mono text-xs text-slate-700">
                      {row.file}
                      {row.error && (
                        <span className="mt-1 block max-w-md whitespace-normal font-sans text-[11px] leading-4 text-red-600">
                          {row.error}
                        </span>
                      )}
                    </td>
                    <td className="px-3 py-3 text-slate-700">{row.provider}</td>
                    <td className="px-3 py-3 text-slate-700">{row.operations}</td>
                    <td className="px-3 py-3 text-slate-700">{row.operations_with_role}</td>
                    <td className="px-3 py-3 font-mono text-blue-600">{row.coverage_percent}%</td>
                    <td className="px-3 py-3 font-mono text-slate-500">{row.contract_coverage_percent}%</td>
                    <td className="px-3 py-3 text-slate-700">{row.warnings}</td>
                    <td className="px-3 py-3 text-slate-700">{row.artifacts}</td>
                    <td className="px-3 py-3">
                      {row.error ? (
                        <span className="font-medium text-red-600">ошибка</span>
                      ) : (
                        <span className="font-medium text-emerald-600">готово</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  )
}

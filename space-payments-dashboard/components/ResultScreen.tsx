// Экран результата: сводные карточки + документ + инспекторская панель.
// Перенесено из screen_docs.html (Stitch), данные — только из summary/API.
'use client'

import { ArrowLeftRight, Compass, Database, Lock, Webhook } from 'lucide-react'

import type { Artifact, Severity, Summary, Warning } from '@/lib/types'
import { ArtifactViewer } from './ArtifactViewer'
import { WarningsPanel } from './WarningsPanel'

type View = 'read' | 'source'

type Source = { file: string; title: string; openapi: string }

type Result = {
  source: Source
  provider: string
  summary: Summary
  warnings: Warning[]
  artifacts: Artifact[]
}

export function ResultScreen({
  result,
  artifacts,
  activeArtifact,
  artifactKind,
  onArtifact,
  view,
  setView,
  warnings,
  filter,
  setFilter,
  expanded,
  setExpanded,
  showAllSignals,
  setShowAllSignals,
  copied,
  copy,
  download,
}: {
  result: Result
  artifacts: Artifact[]
  activeArtifact: Artifact
  artifactKind: string
  onArtifact: (artifact: Artifact) => void
  view: View
  setView: (value: View) => void
  warnings: Warning[]
  filter: 'all' | Severity
  setFilter: (value: 'all' | Severity) => void
  expanded: number | null
  setExpanded: (value: number | null) => void
  showAllSignals: boolean
  setShowAllSignals: (value: boolean) => void
  copied: boolean
  copy: (text: string) => void
  download: () => void
}) {
  const { source, summary } = result

  return (
    <div>
      <div className="mb-6">
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">{result.provider}</h1>
          <span className="inline-flex items-center gap-1.5 rounded-full border border-emerald-200/80 bg-emerald-50 px-2.5 py-0.5 text-xs font-medium text-emerald-700">
            <span className="size-1.5 rounded-full bg-emerald-500" />
            Генерация завершена
          </span>
        </div>
        <p className="mt-1 text-xs text-slate-500">
          Источник: <code className="font-mono text-slate-600">{source.file}</code>
        </p>
      </div>

      <section className="mb-6 grid grid-cols-2 divide-x divide-slate-100 rounded-xl border border-slate-200 bg-white shadow-2xs sm:grid-cols-3 lg:grid-cols-5">
        <MetricCell icon={<Compass className="size-5" strokeWidth={1.8} />} label="OpenAPI" value={source.openapi} />
        <MetricCell
          icon={<ArrowLeftRight className="size-5" strokeWidth={1.8} />}
          label="Операции"
          value={`${summary.operations_with_role}/${summary.operations}`}
        />
        <MetricCell icon={<Database className="size-5" strokeWidth={1.8} />} label="Схемы" value={String(summary.schemas)} />
        <MetricCell icon={<Lock className="size-5" strokeWidth={1.8} />} label="Авторизация" value={summary.auth} />
        <MetricCell
          icon={<Webhook className="size-5" strokeWidth={1.8} />}
          label="Вебхук"
          value={summary.webhook.present ? summary.webhook.signature_header ?? summary.webhook.path ?? 'да' : 'нет'}
        />
      </section>

      <div className="flex flex-col gap-6 lg:flex-row lg:items-start">
        <div className="min-w-0 flex-1">
          <ArtifactViewer
            artifacts={artifacts}
            activeArtifact={activeArtifact}
            onArtifact={onArtifact}
            view={view}
            setView={setView}
            copied={copied}
            copy={copy}
            download={download}
          />
        </div>
        <WarningsPanel
          provider={result.provider}
          summary={summary}
          sourceFile={source.file}
          warnings={warnings}
          filter={filter}
          setFilter={setFilter}
          expanded={expanded}
          setExpanded={setExpanded}
          showAllSignals={showAllSignals}
          setShowAllSignals={setShowAllSignals}
          artifacts={artifacts}
          activeKind={artifactKind}
          onArtifact={onArtifact}
        />
      </div>
    </div>
  )
}

function MetricCell({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="flex min-w-0 items-center gap-3 p-3.5">
      <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-slate-50 text-slate-500">{icon}</div>
      <div className="min-w-0">
        <div className="text-[11px] font-medium leading-none text-slate-400">{label}</div>
        <div className="mt-1 truncate text-sm font-bold leading-tight text-slate-900" title={value}>
          {value}
        </div>
      </div>
    </div>
  )
}

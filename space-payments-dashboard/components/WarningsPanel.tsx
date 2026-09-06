// Правая инспекторская панель: сводка генерации, предупреждения (severity
// warning/error), список выходных файлов, уровень уверенности вывода IR и
// допущения этого прогона. Данные — только из summary/API, ничего не
// вычисляется на фронте.
'use client'

import { useMemo, useState } from 'react'
import ReactMarkdown from 'react-markdown'
import { ChevronDown, ChevronRight, CircleAlert, FileStack, Gauge, Lightbulb, ListChecks, ScrollText } from 'lucide-react'

import type { Artifact, Severity, Summary, Warning } from '@/lib/types'

const SIGNAL_LIMIT = 60

type PanelKey = 'summary' | 'confidence' | 'assumptions' | 'warnings' | 'files'

/** Строка Markdown как обычный текст: заголовки этого текста нам не нужны, только жирный/код. */
function Inline({ text }: { text: string }) {
  return (
    <ReactMarkdown components={{ p: ({ children }) => <>{children}</> }}>{text}</ReactMarkdown>
  )
}

const CONFIDENCE_ROWS: { key: 'structural' | 'overlay' | 'registry' | 'heuristic' | 'unknown'; label: string }[] = [
  { key: 'structural', label: 'из структуры спецификации' },
  { key: 'overlay', label: 'из overlay' },
  { key: 'registry', label: 'по справочнику' },
  { key: 'heuristic', label: 'эвристика' },
  { key: 'unknown', label: 'не выведено' },
]

function ConfidenceBar({ value, total }: { value: number; total: number }) {
  const percent = total > 0 ? Math.round((value / total) * 100) : 0
  return (
    <div className="h-1 w-full overflow-hidden rounded-full bg-slate-100">
      <div className="h-full rounded-full bg-blue-500" style={{ width: `${percent}%` }} />
    </div>
  )
}

function Panel({
  id,
  title,
  badge,
  badgeTone = 'slate',
  icon,
  open,
  onToggle,
  children,
}: {
  id: PanelKey
  title: string
  badge?: number
  badgeTone?: 'slate' | 'amber'
  icon: React.ReactNode
  open: boolean
  onToggle: (id: PanelKey) => void
  children: React.ReactNode
}) {
  return (
    <div className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-2xs">
      <button
        onClick={() => onToggle(id)}
        className="flex w-full items-center justify-between bg-white px-4 py-3 text-left transition-colors hover:bg-slate-50"
      >
        <div className="flex items-center gap-2">
          {icon}
          <span className="text-xs font-bold text-slate-900">{title}</span>
          {badge !== undefined && (
            <span
              className={`flex size-4 items-center justify-center rounded-full text-[10px] font-bold ${
                badgeTone === 'amber' ? 'bg-amber-100 text-amber-700' : 'bg-slate-100 text-slate-600'
              }`}
            >
              {badge}
            </span>
          )}
        </div>
        {open ? (
          <ChevronDown className="size-4 text-slate-400" />
        ) : (
          <ChevronRight className="size-4 text-slate-400" />
        )}
      </button>
      {open && <div className="px-4 pb-4 pt-1">{children}</div>}
    </div>
  )
}

export function WarningsPanel({
  provider,
  summary,
  sourceFile,
  warnings,
  filter,
  setFilter,
  expanded,
  setExpanded,
  showAllSignals,
  setShowAllSignals,
  artifacts,
  activeKind,
  onArtifact,
}: {
  provider: string
  summary: Summary
  sourceFile: string
  warnings: Warning[]
  filter: 'all' | Severity
  setFilter: (value: 'all' | Severity) => void
  expanded: number | null
  setExpanded: (value: number | null) => void
  showAllSignals: boolean
  setShowAllSignals: (value: boolean) => void
  artifacts: Artifact[]
  activeKind: string
  onArtifact: (artifact: Artifact) => void
}) {
  const [open, setOpen] = useState<Record<PanelKey, boolean>>({
    summary: true,
    confidence: true,
    assumptions: false,
    warnings: true,
    files: true,
  })
  const [projectOpen, setProjectOpen] = useState(false)
  const toggle = (id: PanelKey) => setOpen((value) => ({ ...value, [id]: !value[id] }))

  const attention = useMemo(
    () => warnings.filter((item) => item.severity === 'warning' || item.severity === 'error'),
    [warnings],
  )
  const shown = showAllSignals ? warnings : warnings.slice(0, SIGNAL_LIMIT)

  return (
    <aside className="w-80 shrink-0 space-y-4">
      <Panel id="summary" title="Сводка генерации" icon={<ListChecks className="size-4 text-slate-600" />} open={open.summary} onToggle={toggle}>
        <div className="space-y-3.5">
          <div className="flex items-start gap-2.5">
            <div className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full bg-emerald-500 text-white">
              <ListChecks className="size-3" strokeWidth={3} />
            </div>
            <div>
              <div className="text-xs font-bold leading-snug text-slate-900">Успешно сгенерировано</div>
              <div className="mt-0.5 text-[11px] leading-tight text-slate-500">источник: {sourceFile}</div>
            </div>
          </div>
          <div className="space-y-2 border-t border-slate-100 pt-3 text-xs">
            <Row label="Провайдер" value={provider} />
            <Row label="Операции" value={`${summary.operations_with_role} из ${summary.operations}`} />
            <Row label="Схемы" value={String(summary.schemas)} />
            <Row label="Авторизация" value={summary.auth} />
            <Row
              label="Вебхук"
              value={summary.webhook.present ? summary.webhook.signature_header ?? summary.webhook.path ?? 'да' : 'нет'}
            />
          </div>
        </div>
      </Panel>

      <Panel
        id="confidence"
        title="Уровень уверенности"
        icon={<Gauge className="size-4 text-slate-600" />}
        open={open.confidence}
        onToggle={toggle}
      >
        <ConfidenceRows confidence={summary.confidence} />
      </Panel>

      <Panel
        id="assumptions"
        title="Допущения"
        badge={summary.assumptions.run.length}
        icon={<ScrollText className="size-4 text-slate-600" />}
        open={open.assumptions}
        onToggle={toggle}
      >
        <div className="space-y-3">
          {summary.assumptions.run.length > 0 ? (
            <ul className="space-y-2">
              {summary.assumptions.run.map((line, index) => (
                <li key={index} className="flex items-start gap-2 text-xs leading-snug text-slate-700">
                  <span className="mt-1.5 size-1 shrink-0 rounded-full bg-slate-300" />
                  <span className="min-w-0 break-words [overflow-wrap:anywhere]">
                    <Inline text={line} />
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <div className="text-[11px] text-slate-400">Для этого прогона особых допущений нет.</div>
          )}

          <button
            onClick={() => setProjectOpen((value) => !value)}
            className="flex items-center gap-1 text-[11px] font-medium text-blue-600"
          >
            {projectOpen ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />}
            Допущения проекта
          </button>
          {projectOpen && (
            <div className="space-y-2 border-t border-slate-100 pt-2.5 text-[11px] leading-snug text-slate-600">
              <p className="break-words [overflow-wrap:anywhere]">
                <Inline text={summary.assumptions.contract} />
              </p>
              {summary.assumptions.project.map((line, index) => (
                <p key={index} className="break-words [overflow-wrap:anywhere]">
                  <Inline text={line} />
                </p>
              ))}
              <p className="break-words [overflow-wrap:anywhere]">
                <Inline text={summary.assumptions.platform} />
              </p>
            </div>
          )}
        </div>
      </Panel>

      <Panel
        id="warnings"
        title="Требует внимания"
        badge={attention.length}
        badgeTone="amber"
        icon={<CircleAlert className="size-4 text-amber-500" />}
        open={open.warnings}
        onToggle={toggle}
      >
        <select
          value={filter}
          onChange={(event) => {
            setFilter(event.target.value as 'all' | Severity)
            setShowAllSignals(false)
          }}
          className="mb-3 w-full rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-xs text-slate-700"
        >
          <option value="all">Все · {summary.warnings.total}</option>
          <option value="error">Ошибки · {summary.warnings.error}</option>
          <option value="warning">Предупреждения · {summary.warnings.warning}</option>
          <option value="info">Информация · {summary.warnings.info}</option>
        </select>
        <div className="space-y-1">
          {shown.map((warning, index) => (
            <div key={`${warning.code}-${index}`} className="min-w-0 rounded-lg p-2.5 hover:bg-amber-50/50">
              <div className="flex min-w-0 items-start gap-2.5">
                <div
                  className={`mt-0.5 flex size-4 shrink-0 items-center justify-center rounded-full text-[10px] font-bold ${
                    warning.severity === 'error'
                      ? 'bg-red-100 text-red-600'
                      : warning.severity === 'warning'
                        ? 'bg-amber-100 text-amber-600'
                        : 'bg-slate-100 text-slate-500'
                  }`}
                >
                  !
                </div>
                <div className="min-w-0 flex-1">
                  <div className="break-words text-xs font-medium leading-snug text-slate-800 [overflow-wrap:anywhere]">
                    {warning.message}
                  </div>
                  {warning.json_path && (
                    <div className="mt-0.5 break-all font-mono text-[10px] text-slate-400 [overflow-wrap:anywhere]">
                      {warning.json_path}
                    </div>
                  )}
                  {warning.suggested_overlay && (
                    <>
                      <button
                        onClick={() => setExpanded(expanded === index ? null : index)}
                        className="mt-1 text-[10px] font-medium text-blue-600"
                      >
                        {expanded === index ? 'Скрыть overlay' : 'Показать overlay'}
                      </button>
                      {expanded === index && (
                        <pre className="mt-1.5 overflow-x-auto rounded-md bg-slate-50 p-2 text-[10px] leading-4 text-slate-700">
                          <code>{warning.suggested_overlay}</code>
                        </pre>
                      )}
                    </>
                  )}
                </div>
              </div>
            </div>
          ))}
          {warnings.length === 0 && <div className="px-1 py-2 text-[11px] text-slate-400">Ничего не нашлось.</div>}
          {!showAllSignals && warnings.length > SIGNAL_LIMIT && (
            <button onClick={() => setShowAllSignals(true)} className="px-1 pt-1 text-[10px] text-blue-600">
              Показать все {warnings.length}
            </button>
          )}
        </div>
      </Panel>

      <Panel
        id="files"
        title="Выходные файлы"
        badge={artifacts.length}
        icon={<FileStack className="size-4 text-slate-600" />}
        open={open.files}
        onToggle={toggle}
      >
        <div className="space-y-1">
          {artifacts.map((artifact) => (
            <button
              key={artifact.kind}
              onClick={() => onArtifact(artifact)}
              className={`flex w-full items-center justify-between rounded-lg px-2 py-1.5 text-left text-xs ${
                artifact.kind === activeKind ? 'bg-blue-50 font-medium text-blue-700' : 'text-slate-600 hover:bg-slate-50'
              }`}
            >
              <span className="truncate font-mono">{artifact.filename}</span>
              <span className="shrink-0 text-[10px] text-slate-400">{artifact.lines} стр.</span>
            </button>
          ))}
        </div>
      </Panel>

      <div className="flex items-start gap-3 rounded-xl border border-slate-200/80 bg-slate-50 p-3.5">
        <Lightbulb className="mt-0.5 size-4 shrink-0 text-blue-600" />
        <p className="text-xs leading-snug text-slate-600">
          <strong className="font-semibold text-slate-800">Совет:</strong> ознакомьтесь с отчётом обо всех
          допущениях перед развёртыванием в продакшене.
        </p>
      </div>
    </aside>
  )
}

function ConfidenceRows({ confidence }: { confidence: Summary['confidence'] }) {
  const total = confidence.structural + confidence.overlay + confidence.registry + confidence.heuristic + confidence.unknown

  return (
    <div className="space-y-2.5">
      {CONFIDENCE_ROWS.map(({ key, label }) => (
        <div key={key} className="space-y-1">
          <div className="flex items-center justify-between gap-3 text-xs">
            <span className="text-slate-500">{label}</span>
            <span className="font-medium text-slate-800">{confidence[key]}</span>
          </div>
          <ConfidenceBar value={confidence[key]} total={total} />
          {key === 'heuristic' && confidence.heuristic_low > 0 && (
            <div className="flex items-center justify-between gap-3 pl-3 text-[11px] text-slate-400">
              <span>ниже порога (порог {confidence.threshold})</span>
              <span className="font-medium text-slate-500">{confidence.heuristic_low}</span>
            </div>
          )}
        </div>
      ))}
    </div>
  )
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-slate-500">{label}</span>
      <span className="truncate font-medium text-slate-800">{value}</span>
    </div>
  )
}

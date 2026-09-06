'use client'

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import {
  AlertTriangle,
  ArrowLeft,
  Check,
  Clipboard,
  Download,
  FileCode2,
  FileJson,
  FileText,
  FolderOpen,
  GitBranch,
  Loader2,
  Moon,
  Search,
  ShieldCheck,
  Sun,
  Terminal,
  UploadCloud,
  X,
} from 'lucide-react'

import {
  API_BASE,
  MAX_UPLOAD_BYTES,
  UPLOAD_EXTENSIONS,
  describeError,
  generate,
  loadBatch,
  loadSpecs,
  checkHealth,
  type GenerateBody,
} from '@/lib/api'
import { markdownHeadings } from '@/lib/markdown'
import type { Artifact, BatchResponse, BatchRow, Severity, Spec, Summary, Warning } from '@/lib/types'

type Screen = 'upload' | 'result' | 'batch'
type View = 'read' | 'source'
type SortKey = 'coverage_percent' | 'operations' | 'warnings'

/** Откуда взялась спецификация: строка каталога или загруженный файл. */
type Source = { file: string; title: string; openapi: string }

type Result = {
  source: Source
  provider: string
  summary: Summary
  warnings: Warning[]
  artifacts: Artifact[]
}

const formatBytes = (bytes: number) =>
  bytes > 100000 ? `${(bytes / 1000).toFixed(0)} KB` : `${(bytes / 1000).toFixed(1)} KB`

const SIGNAL_LIMIT = 60

function iconFor(language: string) {
  if (language === 'ruby') return <FileCode2 className="size-4" />
  if (language === 'json') return <FileJson className="size-4" />
  return <FileText className="size-4" />
}

function preferredKind(artifacts: Artifact[]) {
  return artifacts.find((item) => item.kind === 'integration')?.kind ?? artifacts[0]?.kind ?? ''
}

export default function Page() {
  const [screen, setScreen] = useState<Screen>('upload')
  const [dark, setDark] = useState(true)
  const [demo, setDemo] = useState(false)
  const [demoDismissed, setDemoDismissed] = useState(false)

  const [specs, setSpecs] = useState<Spec[]>([])
  const [specsLoading, setSpecsLoading] = useState(true)

  const [busy, setBusy] = useState<string | null>(null)
  const [failure, setFailure] = useState<{ message: string; where: string | null } | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const [result, setResult] = useState<Result | null>(null)
  const [artifactKind, setArtifactKind] = useState('')
  const [view, setView] = useState<View>('read')
  const [filter, setFilter] = useState<'all' | Severity>('all')
  const [expanded, setExpanded] = useState<number | null>(null)
  const [showAllSignals, setShowAllSignals] = useState(false)
  const [copied, setCopied] = useState(false)

  const [batch, setBatch] = useState<BatchResponse | null>(null)
  const [batchLoading, setBatchLoading] = useState(false)
  const [batchElapsed, setBatchElapsed] = useState(0)
  const [sortKey, setSortKey] = useState<SortKey>('coverage_percent')

  const fileInput = useRef<HTMLInputElement>(null)

  // Каталог и живость сервера — один раз при открытии: баннер демо-режима
  // должен быть правдой ещё до первой генерации.
  useEffect(() => {
    let alive = true
    void (async () => {
      const [alive_server, catalog] = await Promise.all([checkHealth(), loadSpecs()])
      if (!alive) return
      setSpecs(catalog.data.specs)
      setDemo(catalog.demo || !alive_server)
      setSpecsLoading(false)
    })()
    return () => {
      alive = false
    }
  }, [])

  useEffect(() => {
    if (!batchLoading) return undefined
    const timer = window.setInterval(() => setBatchElapsed((value) => value + 1), 1000)
    return () => window.clearInterval(timer)
  }, [batchLoading])

  const run = useCallback(async (body: GenerateBody, source: Source) => {
    setBusy(source.file)
    setFailure(null)
    setNotice(null)
    try {
      const { data, demo: fromFixtures } = await generate(body)
      setDemo(fromFixtures)
      setResult({ source, provider: data.provider, summary: data.summary, warnings: data.warnings, artifacts: data.artifacts })
      const kind = preferredKind(data.artifacts)
      setArtifactKind(kind)
      setView(data.artifacts.find((item) => item.kind === kind)?.language === 'markdown' ? 'read' : 'source')
      setFilter('all')
      setExpanded(null)
      setShowAllSignals(false)
      setScreen('result')
    } catch (error) {
      setFailure(describeError(error))
    } finally {
      setBusy(null)
    }
  }, [])

  const openBatch = useCallback(async () => {
    setScreen('batch')
    if (batch !== null || batchLoading) return
    setBatchLoading(true)
    setBatchElapsed(0)
    setFailure(null)
    try {
      const { data, demo: fromFixtures } = await loadBatch()
      setBatch(data)
      setDemo(fromFixtures)
    } catch (error) {
      setFailure(describeError(error))
    } finally {
      setBatchLoading(false)
    }
  }, [batch, batchLoading])

  const acceptFile = useCallback(
    async (file: File) => {
      setNotice(null)
      setFailure(null)
      const dot = file.name.lastIndexOf('.')
      const extension = dot === -1 ? '' : file.name.slice(dot).toLowerCase()
      if (!UPLOAD_EXTENSIONS.includes(extension)) {
        setNotice(`Ожидается ${UPLOAD_EXTENSIONS.join(', ')}, а пришёл файл «${file.name}».`)
        return
      }
      if (file.size > MAX_UPLOAD_BYTES) {
        setNotice(`Файл ${formatBytes(file.size)} — больше лимита сервера 5 МБ, он его не примет.`)
        return
      }
      const content = await file.text()
      await run({ filename: file.name, content }, { file: file.name, title: file.name, openapi: '—' })
    },
    [run],
  )

  const copy = useCallback((text: string) => {
    void navigator.clipboard?.writeText(text)
    setCopied(true)
    window.setTimeout(() => setCopied(false), 1200)
  }, [])

  const artifacts = result?.artifacts ?? []
  const activeArtifact = artifacts.find((item) => item.kind === artifactKind) ?? artifacts[0] ?? null

  const download = useCallback(() => {
    if (!activeArtifact) return
    const url = URL.createObjectURL(new Blob([activeArtifact.content], { type: 'text/plain;charset=utf-8' }))
    const link = document.createElement('a')
    link.href = url
    link.download = activeArtifact.filename
    link.click()
    URL.revokeObjectURL(url)
  }, [activeArtifact])

  const filteredWarnings = useMemo(() => {
    const all = result?.warnings ?? []
    return filter === 'all' ? all : all.filter((item) => item.severity === filter)
  }, [result, filter])

  const sortedRows = useMemo(() => {
    const rows = batch?.rows ?? []
    return [...rows].sort((a, b) => b[sortKey] - a[sortKey])
  }, [batch, sortKey])

  return (
    <div className={`${dark ? 'dark' : ''} min-h-screen bg-background text-foreground`}>
      <input
        ref={fileInput}
        type="file"
        accept={UPLOAD_EXTENSIONS.join(',')}
        className="hidden"
        onChange={(event) => {
          const file = event.target.files?.[0]
          event.target.value = ''
          if (file) void acceptFile(file)
        }}
      />
      <header className="border-b border-border bg-background">
        <div className="mx-auto flex h-20 max-w-[1480px] items-center justify-between px-6 lg:px-10">
          <button onClick={() => setScreen('upload')} className="group flex items-center gap-4 text-left">
            <span className="flex size-9 items-center justify-center border border-primary bg-primary text-primary-foreground">
              <Terminal className="size-4" />
            </span>
            <span>
              <span className="block font-mono text-[13px] font-bold tracking-[0.2em]">SPACE / PAYMENTS</span>
              <span className="mt-1 block font-mono text-[10px] uppercase tracking-widest text-muted-foreground">
                spec compiler · 0.1.0
              </span>
            </span>
          </button>
          <div className="flex items-center gap-6">
            <nav className="hidden items-center gap-5 text-[12px] font-medium uppercase tracking-wider md:flex">
              <button
                onClick={() => setScreen('upload')}
                className={screen === 'upload' ? 'text-primary' : 'text-muted-foreground hover:text-foreground'}
              >
                Import
              </button>
              <button
                onClick={() => setScreen('result')}
                disabled={result === null}
                className={`${screen === 'result' ? 'text-primary' : 'text-muted-foreground hover:text-foreground'} disabled:opacity-40`}
              >
                Output
              </button>
              <button
                onClick={() => void openBatch()}
                className={screen === 'batch' ? 'text-primary' : 'text-muted-foreground hover:text-foreground'}
              >
                Registry
              </button>
            </nav>
            <span className="hidden h-4 w-px bg-border md:block" />
            <button
              aria-label="Переключить тему"
              onClick={() => setDark(!dark)}
              className="text-muted-foreground hover:text-primary"
            >
              {dark ? <Sun className="size-4" /> : <Moon className="size-4" />}
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-[1480px] px-6 py-10 lg:px-10">
        {demo && !demoDismissed && (
          <div className="mb-8 flex items-center justify-between border-l-2 border-primary bg-primary/10 px-4 py-3 text-xs">
            <span className="flex items-center gap-2 text-primary">
              <span className="size-1.5 bg-primary" /> DEMO ENVIRONMENT — сервер генератора недоступен, показаны
              сохранённые ответы API
            </span>
            <button aria-label="Скрыть уведомление" onClick={() => setDemoDismissed(true)}>
              <X className="size-3.5 text-muted-foreground" />
            </button>
          </div>
        )}
        {failure && (
          <div className="mb-8 flex items-start justify-between gap-4 border-l-2 border-red-500 bg-red-500/10 px-4 py-3 text-xs">
            <span className="flex items-start gap-2 text-red-500">
              <AlertTriangle className="mt-px size-3.5 shrink-0" />
              <span>
                {failure.message}
                {failure.where && (
                  <span className="mt-1 block font-mono text-[10px] text-muted-foreground">{failure.where}</span>
                )}
              </span>
            </span>
            <button aria-label="Скрыть ошибку" onClick={() => setFailure(null)}>
              <X className="size-3.5 text-muted-foreground" />
            </button>
          </div>
        )}
        {notice && (
          <div className="mb-8 flex items-center justify-between border-l-2 border-amber-400 bg-amber-400/10 px-4 py-3 text-xs">
            <span className="flex items-center gap-2 text-amber-500">
              <AlertTriangle className="size-3.5" /> {notice}
            </span>
            <button aria-label="Скрыть предупреждение" onClick={() => setNotice(null)}>
              <X className="size-3.5 text-muted-foreground" />
            </button>
          </div>
        )}

        {screen === 'upload' && (
          <UploadScreen
            specs={specs}
            loading={specsLoading}
            busy={busy}
            onGenerate={(spec) =>
              void run({ spec_id: spec.id }, { file: spec.file, title: spec.title, openapi: spec.openapi })
            }
            onPick={() => fileInput.current?.click()}
            onDrop={(file) => void acceptFile(file)}
          />
        )}
        {screen === 'result' &&
          (result && activeArtifact ? (
            <ResultScreen
              result={result}
              artifacts={artifacts}
              activeArtifact={activeArtifact}
              artifactKind={artifactKind}
              onArtifact={(artifact) => {
                setArtifactKind(artifact.kind)
                setView(artifact.language === 'markdown' ? 'read' : 'source')
              }}
              view={view}
              setView={setView}
              warnings={filteredWarnings}
              filter={filter}
              setFilter={setFilter}
              expanded={expanded}
              setExpanded={setExpanded}
              showAllSignals={showAllSignals}
              setShowAllSignals={setShowAllSignals}
              copied={copied}
              copy={copy}
              download={download}
              setScreen={setScreen}
            />
          ) : (
            <Empty text="Ещё нечего показывать — выберите спецификацию на экране Import." />
          ))}
        {screen === 'batch' && (
          <BatchScreen
            batch={batch}
            rows={sortedRows}
            loading={batchLoading}
            elapsed={batchElapsed}
            sortKey={sortKey}
            setSortKey={setSortKey}
          />
        )}
      </main>

      <footer className="mx-auto flex max-w-[1480px] items-center justify-between border-t border-border px-6 py-6 font-mono text-[10px] uppercase tracking-wider text-muted-foreground lg:px-10">
        <span>space-payments / ruby generator</span>
        <span className="flex items-center gap-3">
          <span>API · {API_BASE || 'same origin'}</span>
          <GitBranch className="size-3" />
        </span>
      </footer>
    </div>
  )
}

function Empty({ text }: { text: string }) {
  return <div className="border border-dashed border-border px-6 py-16 text-center text-sm text-muted-foreground">{text}</div>
}

function UploadScreen({
  specs,
  loading,
  busy,
  onGenerate,
  onPick,
  onDrop,
}: {
  specs: Spec[]
  loading: boolean
  busy: string | null
  onGenerate: (spec: Spec) => void
  onPick: () => void
  onDrop: (file: File) => void
}) {
  const [over, setOver] = useState(false)
  return (
    <section className="space-y-12">
      <div className="grid gap-10 border-b border-border pb-10 lg:grid-cols-[1.2fr_0.8fr]">
        <div>
          <div className="mb-5 flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.2em] text-primary">
            <span className="size-1.5 bg-primary" /> Input / 01
          </div>
          <h1 className="max-w-3xl text-4xl font-semibold leading-[1.05] tracking-[-0.04em] sm:text-6xl">
            Из OpenAPI-спеки
            <br />
            <span className="text-muted-foreground">в рабочий Ruby-клиент.</span>
          </h1>
        </div>
        <div className="flex flex-col justify-end gap-4 lg:pl-12">
          <p className="max-w-md text-sm leading-6 text-muted-foreground">
            Компилятор для платёжных интеграций. Находит неявные правила в документации, показывает спорные места и
            собирает код, который можно ревьюить.
          </p>
          <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-muted-foreground">
            <ShieldCheck className="size-3.5 text-primary" /> server-side analysis · no black box
          </div>
        </div>
      </div>
      <div className="grid gap-8 lg:grid-cols-[0.8fr_1.2fr]">
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
          className={`flex min-h-64 flex-col justify-between border border-dashed p-6 transition-colors ${
            over ? 'border-primary bg-primary/[0.12]' : 'border-primary/50 bg-primary/[0.04]'
          }`}
        >
          <div className="flex items-start justify-between">
            <UploadCloud className="size-6 text-primary" />
            <span className="font-mono text-[10px] text-muted-foreground">YAML / JSON · до 5 MB</span>
          </div>
          <div>
            <h2 className="text-lg font-medium">Загрузить спецификацию</h2>
            <p className="mt-2 max-w-sm text-sm leading-6 text-muted-foreground">
              Перетащите файл в эту область или выберите его с диска. Сервер принимает .yaml, .yml и .json размером до
              5 МБ.
            </p>
            <button
              onClick={onPick}
              disabled={busy !== null}
              className="mt-5 inline-flex items-center gap-2 border border-border bg-card px-3 py-2 text-xs font-medium hover:border-primary hover:text-primary disabled:opacity-50"
            >
              <FolderOpen className="size-3.5" /> Выбрать файл
            </button>
          </div>
        </div>
        <div>
          <div className="mb-4 flex items-end justify-between border-b border-border pb-3">
            <div>
              <h2 className="font-medium">Примеры в системе</h2>
              <p className="mt-1 text-xs text-muted-foreground">Быстрый старт с сохранёнными спеками</p>
            </div>
            <span className="font-mono text-[10px] text-muted-foreground">
              {loading ? 'LOADING…' : `${specs.length} FILES`}
            </span>
          </div>
          <div className="divide-y divide-border border-y border-border">
            {loading && <div className="py-6 text-xs text-muted-foreground">Читаем каталог спецификаций…</div>}
            {!loading && specs.length === 0 && (
              <div className="py-6 text-xs text-muted-foreground">Каталог пуст.</div>
            )}
            {specs.map((spec) => (
              <div key={spec.id} className="flex items-center justify-between gap-4 py-4">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="truncate font-mono text-xs">{spec.file}</span>
                    {spec.own && (
                      <span className="bg-primary/15 px-1.5 py-0.5 font-mono text-[9px] uppercase text-primary">own</span>
                    )}
                  </div>
                  <div className="mt-1 text-xs text-muted-foreground">
                    {spec.title} · {spec.openapi} · {formatBytes(spec.bytes)}
                  </div>
                </div>
                <button
                  onClick={() => onGenerate(spec)}
                  disabled={busy !== null}
                  className="shrink-0 border border-border px-3 py-2 font-mono text-[10px] uppercase hover:border-primary hover:text-primary disabled:opacity-50"
                >
                  {busy === spec.file ? <Loader2 className="size-3 animate-spin" /> : 'Generate'}
                </button>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}

function ResultScreen({
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
  setScreen,
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
  setScreen: (value: Screen) => void
}) {
  const { source, summary } = result
  const isMarkdown = activeArtifact.language === 'markdown'
  const reading = view === 'read' && isMarkdown
  const documentRef = useRef<HTMLElement>(null)
  const headings = useMemo(() => (isMarkdown ? markdownHeadings(activeArtifact.content) : []), [isMarkdown, activeArtifact])
  const actionable = useMemo(() => result.warnings.filter((item) => item.suggested_overlay), [result])
  const shown = showAllSignals ? warnings : warnings.slice(0, SIGNAL_LIMIT)

  const jump = (index: number) => {
    const nodes = documentRef.current?.querySelectorAll('.markdown-document h2')
    nodes?.[index]?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  return (
    <section className="space-y-8">
      <div className="flex flex-col justify-between gap-6 border-b border-border pb-8 lg:flex-row lg:items-end">
        <div>
          <button
            onClick={() => setScreen('upload')}
            className="mb-5 flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-muted-foreground hover:text-primary"
          >
            <ArrowLeft className="size-3" /> all sources
          </button>
          <div className="flex flex-wrap items-center gap-3">
            <span className="font-mono text-xs text-primary">{source.file}</span>
            <span className="text-border">/</span>
            <h1 className="text-3xl font-semibold tracking-[-0.03em]">{source.title}</h1>
          </div>
          <p className="mt-3 text-sm text-muted-foreground">
            Compilation complete · артефактов: {artifacts.length}
          </p>
        </div>
        <div className="flex items-end gap-8">
          <div>
            <div className="font-mono text-5xl tracking-[-0.08em]">
              {summary.coverage_percent}
              <span className="text-2xl text-primary">%</span>
            </div>
            <div className="mt-1 font-mono text-[10px] uppercase tracking-widest text-muted-foreground">coverage</div>
          </div>
          <div className="h-12 w-px bg-border" />
          <div>
            <div className="font-mono text-5xl tracking-[-0.08em]">
              {summary.contract_coverage_percent}
              <span className="text-2xl text-primary">%</span>
            </div>
            <div className="mt-1 font-mono text-[10px] uppercase tracking-widest text-muted-foreground">
              in contract
            </div>
          </div>
          <div className="h-12 w-px bg-border" />
          <div className="pb-1 text-right font-mono text-xs text-muted-foreground">
            <div className="text-foreground">
              {summary.operations_with_role} / {summary.operations}
            </div>
            <div>operations mapped</div>
          </div>
        </div>
      </div>

      <div className="grid gap-px bg-border md:grid-cols-4">
        <Metric
          label="Операции"
          value={`${summary.operations_with_role} из ${summary.operations}`}
          detail={`покрытие ${summary.coverage_percent}% · в контракте ${summary.contract_coverage_percent}%`}
        />
        <Metric label="Схемы" value={`${summary.schemas}`} detail={`полей: ${summary.fields}`} />
        <Metric
          label="Статусы"
          value={`${summary.statuses.mapped} из ${summary.statuses.total}`}
          detail={`события: ${summary.events.mapped} из ${summary.events.total}`}
        />
        <Metric
          label="Сигналы"
          value={`${summary.warnings.total}`}
          detail={`ошибок ${summary.warnings.error} · предупреждений ${summary.warnings.warning} · инфо ${summary.warnings.info}`}
        />
      </div>

      <div className="grid gap-px bg-border lg:grid-cols-2">
        <Fact label="Авторизация" value={summary.auth} />
        <Fact label="Единицы суммы" value={summary.units} />
        <Fact label="Базовый адрес" value={summary.base_url ?? 'не выведен'} mono />
        <Fact
          label="Вебхук"
          value={
            summary.webhook.present
              ? `${summary.webhook.path ?? '—'}${summary.webhook.signature_header ? ` · подпись в ${summary.webhook.signature_header}` : ' · заголовок подписи не найден'}`
              : 'в спецификации нет'
          }
          mono
        />
      </div>

      <div className="workspace-grid">
        <aside className="workspace-sidebar">
          <div className="sticky top-6">
            <div className="mb-4 text-[11px] font-semibold text-muted-foreground">Документ</div>
            <div className="space-y-1">
              {artifacts.map((artifact) => (
                <button
                  key={artifact.kind}
                  onClick={() => onArtifact(artifact)}
                  className={`flex w-full items-center gap-3 px-3 py-2.5 text-left text-sm ${
                    artifactKind === artifact.kind
                      ? 'bg-primary/10 font-medium text-primary'
                      : 'text-muted-foreground hover:bg-muted hover:text-foreground'
                  }`}
                >
                  {iconFor(artifact.language)}
                  <span className="truncate">{artifact.filename}</span>
                </button>
              ))}
            </div>
            {reading && headings.length > 0 && (
              <div className="mt-8 border-t border-border pt-5">
                <div className="mb-3 text-[11px] font-semibold text-muted-foreground">Разделы</div>
                {headings.map((heading, index) => (
                  <button
                    key={`${heading}-${index}`}
                    onClick={() => jump(index)}
                    className="block w-full py-1.5 text-left text-xs text-muted-foreground hover:text-primary"
                  >
                    {heading}
                  </button>
                ))}
              </div>
            )}
          </div>
        </aside>

        <article ref={documentRef} className="document-surface">
          <div className="document-toolbar">
            <div>
              <div className="font-mono text-[10px] uppercase tracking-wider text-muted-foreground">
                Generated artifact
              </div>
              <h2 className="mt-1 text-lg font-semibold">{activeArtifact.filename}</h2>
            </div>
            <div className="flex items-center gap-1 border border-border p-1">
              <button
                onClick={() => setView('read')}
                disabled={!isMarkdown}
                className={`px-3 py-1.5 text-xs ${
                  reading ? 'bg-primary text-primary-foreground' : 'text-muted-foreground disabled:opacity-50'
                }`}
              >
                Read
              </button>
              <button
                onClick={() => setView('source')}
                className={`px-3 py-1.5 text-xs ${
                  !reading ? 'bg-primary text-primary-foreground' : 'text-muted-foreground'
                }`}
              >
                Source
              </button>
            </div>
          </div>
          <div className="document-meta">
            <span>{activeArtifact.language}</span>
            <span>{activeArtifact.lines} lines</span>
            <span>{formatBytes(activeArtifact.bytes)}</span>
            <span className="ml-auto flex gap-3">
              <button
                onClick={() => copy(activeArtifact.content)}
                className="inline-flex items-center gap-1.5 hover:text-primary"
              >
                {copied ? <Check className="size-3" /> : <Clipboard className="size-3" />} {copied ? 'copied' : 'copy'}
              </button>
              <button onClick={download} className="inline-flex items-center gap-1.5 hover:text-primary">
                <Download className="size-3" /> save
              </button>
            </span>
          </div>
          {reading ? (
            <div className="markdown-document">
              <ReactMarkdown remarkPlugins={[remarkGfm]}>{activeArtifact.content}</ReactMarkdown>
            </div>
          ) : (
            <pre className="source-document">
              <code>{activeArtifact.content}</code>
            </pre>
          )}
        </article>

        <aside className="workspace-rail">
          <div className="sticky top-6 space-y-8">
            <div>
              <div className="mb-3 text-[11px] font-semibold text-muted-foreground">Источник</div>
              <div className="space-y-2 text-xs">
                <div className="flex justify-between gap-4">
                  <span className="text-muted-foreground">Провайдер</span>
                  <span className="font-mono">{result.provider}</span>
                </div>
                <div className="flex justify-between gap-4">
                  <span className="text-muted-foreground">OpenAPI</span>
                  <span>{source.openapi}</span>
                </div>
                <div className="flex justify-between gap-4">
                  <span className="text-muted-foreground">Idempotency</span>
                  <span className="font-mono">{summary.idempotency_header ?? 'нет'}</span>
                </div>
              </div>
            </div>

            {actionable.length > 0 && (
              <div>
                <div className="mb-3 flex items-center justify-between text-[11px] font-semibold text-muted-foreground">
                  <span>Решения</span>
                  <span className="font-mono text-[10px]">{actionable.length}</span>
                </div>
                <div className="space-y-3">
                  {actionable.slice(0, 3).map((warning, index) => (
                    <div key={`${warning.code}-${index}`} className="border-l-2 border-amber-400 pl-3">
                      <div className="text-xs font-medium">{warning.code}</div>
                      <div className="mt-1 text-[11px] leading-4 text-muted-foreground">{warning.message}</div>
                      <button
                        onClick={() => setExpanded(expanded === index ? null : index)}
                        className="mt-2 text-[10px] text-primary"
                      >
                        {expanded === index ? 'Скрыть overlay' : 'Показать overlay'}
                      </button>
                      {expanded === index && (
                        <pre className="mt-2 overflow-x-auto bg-muted p-2 text-[10px] leading-4">
                          <code>{warning.suggested_overlay}</code>
                        </pre>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div>
              <div className="mb-3 text-[11px] font-semibold text-muted-foreground">Все сигналы</div>
              <select
                value={filter}
                onChange={(event) => {
                  setFilter(event.target.value as 'all' | Severity)
                  setShowAllSignals(false)
                }}
                className="w-full border border-border bg-card px-2 py-2 text-xs"
              >
                <option value="all">Все · {summary.warnings.total}</option>
                <option value="error">Ошибки · {summary.warnings.error}</option>
                <option value="warning">Предупреждения · {summary.warnings.warning}</option>
                <option value="info">Информация · {summary.warnings.info}</option>
              </select>
              <div className="mt-3 space-y-2">
                {shown.map((warning, index) => (
                  <div key={`${warning.code}-${index}`} className="flex gap-2 text-[11px]">
                    <span
                      className={`mt-1 size-1.5 shrink-0 rounded-full ${
                        warning.severity === 'error'
                          ? 'bg-red-500'
                          : warning.severity === 'warning'
                            ? 'bg-amber-400'
                            : 'bg-primary'
                      }`}
                    />
                    <span>
                      <span className="text-muted-foreground">{warning.message}</span>
                      {warning.json_path && (
                        <span className="mt-0.5 block break-all font-mono text-[9px] text-muted-foreground/70">
                          {warning.json_path}
                        </span>
                      )}
                    </span>
                  </div>
                ))}
                {warnings.length === 0 && <div className="text-[11px] text-muted-foreground">Ничего не нашлось.</div>}
                {!showAllSignals && warnings.length > SIGNAL_LIMIT && (
                  <button onClick={() => setShowAllSignals(true)} className="pt-1 text-[10px] text-primary">
                    Показать все {warnings.length}
                  </button>
                )}
              </div>
            </div>
          </div>
        </aside>
      </div>
    </section>
  )
}

function Metric({ label, value, detail }: { label: string; value: string; detail: string }) {
  return (
    <div className="bg-card p-4">
      <div className="font-mono text-[10px] uppercase tracking-widest text-muted-foreground">{label}</div>
      <div className="mt-4 text-lg font-medium">{value}</div>
      <div className="mt-1 font-mono text-[10px] text-primary">{detail}</div>
    </div>
  )
}

/** Готовая строка от сервера. Печатается как есть — разбирать её нельзя. */
function Fact({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="bg-card p-4">
      <div className="font-mono text-[10px] uppercase tracking-widest text-muted-foreground">{label}</div>
      <div className={`mt-2 text-xs leading-5 ${mono ? 'break-all font-mono' : ''}`}>{value}</div>
    </div>
  )
}

function BatchScreen({
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
  const labels: Record<SortKey, string> = {
    coverage_percent: 'coverage',
    operations: 'operations',
    warnings: 'warnings',
  }
  return (
    <section className="space-y-8">
      <div className="flex flex-col justify-between gap-5 border-b border-border pb-8 md:flex-row md:items-end">
        <div>
          <div className="mb-5 flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.2em] text-primary">
            <span className="size-1.5 bg-primary" /> Registry / 03
          </div>
          <h1 className="text-4xl font-semibold tracking-[-0.04em]">Все провайдеры</h1>
          <p className="mt-3 max-w-xl text-sm leading-6 text-muted-foreground">
            Batch-сводка по источникам в репозитории: каждый файл прогоняется через весь конвейер целиком.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Search className="size-4 text-muted-foreground" />
          <span className="font-mono text-xs text-muted-foreground">
            {batch ? `${batch.generated} / ${batch.total} sources` : '—'}
          </span>
        </div>
      </div>

      {loading && (
        <div className="space-y-3 border border-border p-6">
          <div className="flex items-center gap-3 text-sm">
            <Loader2 className="size-4 animate-spin text-primary" />
            Конвейер идёт по всему каталогу — это занимает 10–20 секунд. Прошло: {elapsed} с.
          </div>
          <div className="h-1 w-full overflow-hidden bg-muted">
            <div className="h-full w-1/3 animate-pulse bg-primary" />
          </div>
        </div>
      )}

      {!loading && rows.length === 0 && <Empty text="Пакетный прогон ничего не вернул." />}

      {rows.length > 0 && (
        <>
          <div className="flex gap-2">
            {(Object.keys(labels) as SortKey[]).map((key) => (
              <button
                key={key}
                onClick={() => setSortKey(key)}
                className={`border px-3 py-2 font-mono text-[10px] uppercase ${
                  sortKey === key ? 'border-primary text-primary' : 'border-border text-muted-foreground'
                }`}
              >
                {labels[key]}
              </button>
            ))}
          </div>
          <div className="overflow-x-auto border-y border-border">
            <table className="w-full min-w-[760px] text-left text-sm">
              <thead>
                <tr className="font-mono text-[10px] uppercase text-muted-foreground">
                  <th className="px-4 py-4">Source</th>
                  <th>Provider</th>
                  <th>Ops</th>
                  <th>Mapped</th>
                  <th>Coverage</th>
                  <th>In contract</th>
                  <th>Signals</th>
                  <th>Files</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {rows.map((row) => (
                  <tr key={row.file} className="align-top hover:bg-muted/50">
                    <td className="px-4 py-4 font-mono text-xs">
                      {row.file}
                      {row.error && (
                        <span className="mt-1 block max-w-md whitespace-normal font-sans text-[11px] leading-4 text-red-500">
                          {row.error}
                        </span>
                      )}
                    </td>
                    <td className="py-4">{row.provider}</td>
                    <td className="py-4">{row.operations}</td>
                    <td className="py-4">{row.operations_with_role}</td>
                    <td className="py-4 font-mono text-primary">{row.coverage_percent}%</td>
                    <td className="py-4 font-mono text-muted-foreground">{row.contract_coverage_percent}%</td>
                    <td className="py-4">{row.warnings}</td>
                    <td className="py-4">{row.artifacts}</td>
                    <td className="py-4">
                      {row.error ? <span className="text-red-500">error</span> : <span className="text-primary">ready</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </section>
  )
}

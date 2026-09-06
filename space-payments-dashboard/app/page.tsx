'use client'

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { AlertTriangle, ChevronRight, X } from 'lucide-react'

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
import type { RunOptions } from '@/lib/api'
import type { Artifact, BatchResponse, BatchRow, Severity, Spec, Summary, Warning } from '@/lib/types'

import { BatchScreen, type SortKey } from '@/components/BatchScreen'
import { ResultScreen } from '@/components/ResultScreen'
import { Sidebar, type Screen } from '@/components/Sidebar'
import { UploadScreen } from '@/components/UploadScreen'

type View = 'read' | 'source'

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
  bytes > 100000 ? `${(bytes / 1000).toFixed(0)} КБ` : `${(bytes / 1000).toFixed(1)} КБ`

const SCREEN_TITLES: Record<Screen, string> = {
  upload: 'Новый прогон',
  result: 'Результат',
  batch: 'Пакетный прогон',
}

function preferredKind(artifacts: Artifact[]) {
  return artifacts.find((item) => item.kind === 'integration')?.kind ?? artifacts[0]?.kind ?? ''
}

export default function Page() {
  const [screen, setScreen] = useState<Screen>('upload')
  const [online, setOnline] = useState(true)
  const [demo, setDemo] = useState(false)
  const [demoDismissed, setDemoDismissed] = useState(false)

  const [specs, setSpecs] = useState<Spec[]>([])
  const [specsLoading, setSpecsLoading] = useState(true)
  const [runOptions, setRunOptions] = useState<RunOptions>({})

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

  // Каталог и живость сервера — один раз при открытии: индикатор демо-режима
  // должен быть правдой ещё до первой генерации.
  useEffect(() => {
    let alive = true
    void (async () => {
      const [aliveServer, catalog] = await Promise.all([checkHealth(), loadSpecs()])
      if (!alive) return
      setSpecs(catalog.data.specs)
      setOnline(aliveServer)
      setDemo(catalog.demo || !aliveServer)
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

  const navigate = useCallback(
    (target: Screen) => {
      if (target === 'batch') {
        void openBatch()
        return
      }
      setScreen(target)
    },
    [openBatch],
  )

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
      await run(
        { filename: file.name, content, ...runOptions },
        { file: file.name, title: file.name, openapi: '—' },
      )
    },
    [run, runOptions],
  )

  const acceptPaste = useCallback(
    async (content: string, filename: string) => {
      setNotice(null)
      setFailure(null)
      const text = content.trim()
      if (text.length === 0) return
      if (new Blob([text]).size > MAX_UPLOAD_BYTES) {
        setNotice('Вставленный текст больше лимита сервера 5 МБ, он его не примет.')
        return
      }
      const name = filename.trim().length > 0 ? filename.trim() : 'spec.yaml'
      await run({ filename: name, content: text, ...runOptions }, { file: name, title: name, openapi: '—' })
    },
    [run, runOptions],
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
    <div className="flex h-screen overflow-hidden bg-slate-50/50 text-slate-800">
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

      <Sidebar screen={screen} hasResult={result !== null} onNavigate={navigate} online={online} demo={demo} />

      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <header className="flex h-14 shrink-0 items-center justify-between border-b border-slate-200 bg-white px-6">
          <nav className="flex min-w-0 items-center gap-2 text-xs font-medium text-slate-500">
            <span>specgen</span>
            <ChevronRight className="size-3.5 shrink-0 text-slate-400" />
            {screen === 'result' && result ? (
              <>
                <button onClick={() => setScreen('upload')} className="transition-colors hover:text-slate-900">
                  {SCREEN_TITLES.upload}
                </button>
                <ChevronRight className="size-3.5 shrink-0 text-slate-400" />
                <span className="truncate font-semibold text-slate-900">{result.provider}</span>
              </>
            ) : (
              <span className="font-semibold text-slate-900">{SCREEN_TITLES[screen]}</span>
            )}
          </nav>
          <span className="shrink-0 font-mono text-[11px] text-slate-400">API: {API_BASE || 'same origin'}</span>
        </header>

        <main className="flex-1 overflow-y-auto px-8 py-6">
          <div className="mx-auto w-full max-w-[1400px] space-y-6">
            {demo && !demoDismissed && (
              <Banner tone="info" onDismiss={() => setDemoDismissed(true)}>
                Демо-режим — сервер генератора недоступен, показаны сохранённые ответы API.
              </Banner>
            )}
            {failure && (
              <Banner tone="error" onDismiss={() => setFailure(null)}>
                {failure.message}
                {failure.where && <span className="mt-1 block font-mono text-[11px] text-red-500/80">{failure.where}</span>}
              </Banner>
            )}
            {notice && (
              <Banner tone="warning" onDismiss={() => setNotice(null)}>
                {notice}
              </Banner>
            )}

            {screen === 'upload' && (
              <UploadScreen
                specs={specs}
                loading={specsLoading}
                busy={busy}
                options={runOptions}
                onOptionsChange={setRunOptions}
                onGenerate={(spec) =>
                  void run(
                    { spec_id: spec.id, ...runOptions },
                    { file: spec.file, title: spec.title, openapi: spec.openapi },
                  )
                }
                onPick={() => fileInput.current?.click()}
                onDrop={(file) => void acceptFile(file)}
                onPaste={(content, filename) => void acceptPaste(content, filename)}
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
                />
              ) : (
                <div className="rounded-xl border border-dashed border-slate-300 px-6 py-16 text-center text-sm text-slate-400">
                  Ещё нечего показывать — выберите спецификацию на экране «Новый прогон».
                </div>
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
          </div>
        </main>
      </div>
    </div>
  )
}

function Banner({
  tone,
  onDismiss,
  children,
}: {
  tone: 'info' | 'warning' | 'error'
  onDismiss: () => void
  children: React.ReactNode
}) {
  const palette = {
    info: 'border-blue-200 bg-blue-50 text-blue-700',
    warning: 'border-amber-200 bg-amber-50 text-amber-700',
    error: 'border-red-200 bg-red-50 text-red-700',
  }[tone]
  return (
    <div className={`flex items-start justify-between gap-4 rounded-xl border px-4 py-3 text-xs ${palette}`}>
      <span className="flex items-start gap-2">
        <AlertTriangle className="mt-px size-3.5 shrink-0" />
        <span>{children}</span>
      </span>
      <button aria-label="Скрыть уведомление" onClick={onDismiss} className="shrink-0">
        <X className="size-3.5 opacity-60 hover:opacity-100" />
      </button>
    </div>
  )
}

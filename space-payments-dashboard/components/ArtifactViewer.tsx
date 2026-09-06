// Карточка документа: переключатель файла, режим Рендер/Исходный код,
// копирование и скачивание. Перенесено из screen_docs.html (Stitch).
'use client'

import { useMemo, useRef, useState } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { ChevronDown, ChevronRight, Check, Clipboard, Download, FileCode2, FileJson, FileText } from 'lucide-react'

import { markdownHeadings } from '@/lib/markdown'
import type { Artifact } from '@/lib/types'

type View = 'read' | 'source'

const formatBytes = (bytes: number) =>
  bytes > 100000 ? `${(bytes / 1000).toFixed(0)} КБ` : `${(bytes / 1000).toFixed(1)} КБ`

function iconFor(language: string) {
  if (language === 'ruby') return <FileCode2 className="size-4 text-slate-500" />
  if (language === 'json') return <FileJson className="size-4 text-slate-500" />
  return <FileText className="size-4 text-slate-500" />
}

export function ArtifactViewer({
  artifacts,
  activeArtifact,
  onArtifact,
  view,
  setView,
  copied,
  copy,
  download,
}: {
  artifacts: Artifact[]
  activeArtifact: Artifact
  onArtifact: (artifact: Artifact) => void
  view: View
  setView: (value: View) => void
  copied: boolean
  copy: (text: string) => void
  download: () => void
}) {
  const [pickerOpen, setPickerOpen] = useState(false)
  const [outlineOpen, setOutlineOpen] = useState(false)
  const documentRef = useRef<HTMLDivElement>(null)

  const isMarkdown = activeArtifact.language === 'markdown'
  const reading = view === 'read' && isMarkdown
  const headings = useMemo(
    () => (isMarkdown ? markdownHeadings(activeArtifact.content) : []),
    [isMarkdown, activeArtifact],
  )

  const jump = (index: number) => {
    documentRef.current?.querySelectorAll('h2')[index]?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  return (
    <article className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-2xs">
      <div className="flex h-12 items-center justify-between border-b border-slate-200 px-4">
        <div className="relative">
          <button
            onClick={() => setPickerOpen((value) => !value)}
            className="flex items-center gap-2 text-xs font-semibold text-slate-900 transition-colors hover:text-slate-600"
          >
            {iconFor(activeArtifact.language)}
            <span>{activeArtifact.filename}</span>
            <ChevronDown className="size-3.5 text-slate-400" />
          </button>
          {pickerOpen && (
            <>
              <div className="fixed inset-0 z-10" onClick={() => setPickerOpen(false)} />
              <div className="absolute left-0 top-full z-20 mt-2 w-64 rounded-lg border border-slate-200 bg-white py-1 shadow-lg">
                {artifacts.map((artifact) => (
                  <button
                    key={artifact.kind}
                    onClick={() => {
                      onArtifact(artifact)
                      setPickerOpen(false)
                    }}
                    className={`flex w-full items-center gap-2.5 px-3 py-2 text-left text-xs ${
                      artifact.kind === activeArtifact.kind
                        ? 'bg-blue-50 font-medium text-blue-700'
                        : 'text-slate-700 hover:bg-slate-50'
                    }`}
                  >
                    {iconFor(artifact.language)}
                    <span className="truncate">{artifact.filename}</span>
                  </button>
                ))}
              </div>
            </>
          )}
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center rounded-md bg-slate-100 p-0.5 text-xs font-medium text-slate-600">
            <button
              onClick={() => setView('read')}
              disabled={!isMarkdown}
              className={`rounded px-2.5 py-1 transition-colors ${
                reading ? 'bg-white font-semibold text-blue-700 shadow-2xs' : 'disabled:opacity-40'
              }`}
            >
              Рендер
            </button>
            <button
              onClick={() => setView('source')}
              className={`rounded px-2.5 py-1 transition-colors ${
                !reading ? 'bg-white font-semibold text-blue-700 shadow-2xs' : 'hover:text-slate-900'
              }`}
            >
              Исходный код
            </button>
          </div>
          <div className="h-4 w-px bg-slate-200" />
          <button
            onClick={() => copy(activeArtifact.content)}
            className="flex items-center gap-1.5 rounded-md border border-slate-200 bg-white px-2.5 py-1 text-xs font-medium text-slate-700 transition-colors hover:bg-slate-50"
          >
            {copied ? <Check className="size-3.5 text-emerald-600" /> : <Clipboard className="size-3.5 text-slate-500" />}
            <span>{copied ? 'Скопировано' : 'Копировать'}</span>
          </button>
          <button
            onClick={download}
            className="flex items-center gap-1.5 rounded-md border border-slate-200 bg-white px-2.5 py-1 text-xs font-medium text-slate-700 transition-colors hover:bg-slate-50"
          >
            <Download className="size-3.5 text-slate-500" />
            <span>Скачать</span>
          </button>
        </div>
      </div>

      <div className="p-8">
        {reading && headings.length > 0 && (
          <div className="mb-6">
            <button
              onClick={() => setOutlineOpen((value) => !value)}
              className="inline-flex items-center gap-1 text-xs font-medium text-blue-600 hover:text-blue-700"
            >
              {outlineOpen ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />}
              <span>На этой странице</span>
            </button>
            {outlineOpen && (
              <div className="mt-2 space-y-1 border-l border-slate-200 pl-3">
                {headings.map((heading, index) => (
                  <button
                    key={`${heading}-${index}`}
                    onClick={() => jump(index)}
                    className="block text-left text-xs text-slate-500 hover:text-blue-600"
                  >
                    {heading}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}

        <div className="mb-4 flex items-center gap-3 font-mono text-[11px] uppercase tracking-wide text-slate-400">
          <span>{activeArtifact.language}</span>
          <span>·</span>
          <span>{activeArtifact.lines} строк</span>
          <span>·</span>
          <span>{formatBytes(activeArtifact.bytes)}</span>
        </div>

        {reading ? (
          <div ref={documentRef} className="markdown-document">
            <ReactMarkdown remarkPlugins={[remarkGfm]}>{activeArtifact.content}</ReactMarkdown>
          </div>
        ) : (
          <pre className="source-document rounded-lg">
            <code>{activeArtifact.content}</code>
          </pre>
        )}
      </div>
    </article>
  )
}

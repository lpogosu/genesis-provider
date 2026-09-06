// Левая боковая панель. Только реальные экраны: загрузка/результат и
// пакетный прогон — без выдуманных «Песочницы» и «Настроек» из макета Stitch.
'use client'

import { FileStack, ListTree, UploadCloud } from 'lucide-react'

export type Screen = 'upload' | 'result' | 'batch'

export function Sidebar({
  screen,
  hasResult,
  onNavigate,
  online,
  demo,
}: {
  screen: Screen
  hasResult: boolean
  onNavigate: (screen: Screen) => void
  online: boolean
  demo: boolean
}) {
  const items: { key: Screen; label: string; icon: typeof UploadCloud; disabled?: boolean }[] = [
    { key: 'upload', label: 'Новый прогон', icon: UploadCloud },
    { key: 'result', label: 'Результат', icon: FileStack, disabled: !hasResult },
    { key: 'batch', label: 'Пакетный прогон', icon: ListTree },
  ]

  return (
    <aside className="flex w-60 shrink-0 select-none flex-col justify-between border-r border-slate-200 bg-white">
      <div>
        <div className="flex h-16 items-center gap-3 px-6">
          <div className="flex size-8 items-center justify-center rounded-lg bg-blue-600 font-bold text-white shadow-sm shadow-blue-500/30">
            <span className="text-lg leading-none tracking-tight">S</span>
          </div>
          <span className="text-xl font-bold tracking-tight text-slate-900">specgen</span>
        </div>
        <nav className="mt-4 space-y-1 px-3">
          {items.map((item) => {
            const Icon = item.icon
            const active = screen === item.key
            return (
              <button
                key={item.key}
                onClick={() => onNavigate(item.key)}
                disabled={item.disabled}
                className={`flex w-full items-center gap-3 rounded-xl px-3.5 py-2.5 text-left text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${
                  active
                    ? 'bg-blue-50 text-blue-600'
                    : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'
                }`}
              >
                <Icon className={`size-5 ${active ? 'text-blue-600' : 'text-slate-400'}`} />
                <span>{item.label}</span>
              </button>
            )
          })}
        </nav>
      </div>
      <div className="space-y-2 border-t border-slate-100 p-4">
        <div className="flex items-center gap-2 rounded-xl px-2 py-1.5 text-xs">
          <span className={`size-1.5 rounded-full ${online ? 'bg-emerald-500' : 'bg-amber-500'}`} />
          <span className="font-medium text-slate-600">
            {demo ? 'Демо-режим' : online ? 'Сервер на связи' : 'Сервер недоступен'}
          </span>
        </div>
      </div>
    </aside>
  )
}

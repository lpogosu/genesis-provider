import type { Metadata, Viewport } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Space Payments — генератор интеграций',
  description: 'Генератор Ruby-интеграций для платёжных провайдеров из OpenAPI-спецификаций.',
  generator: 'Space Payments',
}

export const viewport: Viewport = {
  colorScheme: 'light dark',
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f8f9fb' },
    { media: '(prefers-color-scheme: dark)', color: '#20242d' },
  ],
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ru" className="bg-background">
      <body className="antialiased">{children}</body>
    </html>
  )
}

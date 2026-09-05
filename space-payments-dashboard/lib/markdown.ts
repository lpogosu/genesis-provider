// Оглавление документа. Единственное вычисление на клиенте: это разбор
// текста ради навигации, а не предметная логика — ни одного знания о
// платёжных провайдерах здесь нет.

const FENCE = /^\s*(```|~~~)/
const HEADING = /^##\s+(.+?)\s*#*\s*$/

/**
 * Заголовки второго уровня в порядке появления. Строки внутри блоков кода
 * пропускаются: `## что-то` в примере кода — не заголовок.
 */
export function markdownHeadings(source: string): string[] {
  const headings: string[] = []
  let inFence = false
  for (const line of source.split('\n')) {
    if (FENCE.test(line)) {
      inFence = !inFence
      continue
    }
    if (inFence) continue
    const match = HEADING.exec(line)
    if (match) headings.push(match[1].replace(/[*`_]/g, ''))
  }
  return headings
}

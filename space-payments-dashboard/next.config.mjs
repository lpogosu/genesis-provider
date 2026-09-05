/** @type {import('next').NextConfig} */
const nextConfig = {
  // Статический экспорт: `next build` кладёт готовую страницу в out/,
  // её отдаёт Ruby-сервер из public/. Node в рантайме не нужен.
  output: 'export',
  // `next dev` иначе кладёт рядом свои AGENTS.md и CLAUDE.md; конституция
  // проекта одна, и лежит она в корне репозитория.
  agentRules: false,
  images: {
    unoptimized: true,
  },
}

export default nextConfig

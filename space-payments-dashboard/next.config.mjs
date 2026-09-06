/** @type {import('next').NextConfig} */
const nextConfig = {
  // Статический экспорт: `next build` кладёт готовую страницу в out/,
  // её отдаёт Ruby-сервер из public/. Node в рантайме не нужен.
  output: 'export',
  // `next dev` иначе кладёт рядом служебные файлы для
  // ИИ-ассистентов; в репозитории им не место.
  agentRules: false,
  images: {
    unoptimized: true,
  },
}

export default nextConfig

# Образ с генератором: тот же инструмент, что запускается из репозитория,
# только на чистой машине. Одна команда поднимает веб-интерфейс, другая
# гоняет CLI по всем спецификациям — жюри не нужно ставить ни Ruby, ни Node.
#
#   docker build -t specgen .
#   docker run --rm -p 9292:9292 specgen          # веб-интерфейс на 9292
#   docker run --rm specgen ./integrate --all     # пакетный прогон в консоли

# Первая стадия собирает фронт. Node нужен только здесь: `output: 'export'`
# в next.config.mjs даёт статику, и в рантайме её отдаёт Ruby-сервер. В
# итоговый образ ни Node, ни node_modules не попадают.
FROM node:22-slim AS front
WORKDIR /front
RUN corepack enable
# Манифесты отдельным слоем: правка компонентов не переустанавливает
# зависимости. pnpm-workspace.yaml нужен pnpm, без него install ругается.
COPY space-payments-dashboard/package.json space-payments-dashboard/pnpm-lock.yaml \
     space-payments-dashboard/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY space-payments-dashboard/ ./
RUN pnpm build

FROM ruby:3.4-slim

# Ruby печатает и читает UTF-8: заголовки спецификаций и весь наш вывод —
# по-русски, а в slim-образе локаль по умолчанию POSIX.
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Гемы лежат вне /app, поэтому COPY исходников их не затирает.
ENV BUNDLE_PATH=/usr/local/bundle
# В образе приложения нужны rack, thor и json_schemer: rspec, rubocop и
# webmock — инструменты разработки, в поставке им делать нечего.
ENV BUNDLE_WITHOUT=development:test
# Расхождение Gemfile и Gemfile.lock должно ронять сборку, а не молча
# ставить другую версию.
ENV BUNDLE_FROZEN=1

# Адрес и порт сервера читает bin/serve; порт наружу открыт ниже.
ENV HOST=0.0.0.0
ENV PORT=9292

WORKDIR /app

# Зависимости отдельным слоем: правка исходников не пересобирает bundle.
#
# Компилятор нужен ровно на время установки. Сам инструмент чистый Ruby, но
# json_schemer тянет bigdecimal, а тот в Ruby 3.4 стал bundled gem с
# нативным расширением, и в slim-образе собрать его нечем. Ставим
# build-essential, собираем гемы, сносим его в том же слое — иначе
# компилятор остался бы в поставке, а образ вырос бы вдвое.
COPY Gemfile Gemfile.lock ./
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && bundle install \
 && apt-get purge -y --auto-remove build-essential \
 && rm -rf /var/lib/apt/lists/*

COPY . .

# Права на исполнение: на Windows-хосте бит `x` в индексе git не хранится,
# а запускать нужно и CLI, и сервер.
RUN chmod +x integrate bin/integrate bin/serve

# Собранный фронт из первой стадии. Каталог public/ отдаётся автоматически,
# если он есть: SpecGen::Web::Static проверяет его наличие на каждом запросе,
# и без него сервер поднимается — тогда работает только API.
COPY --from=front /front/out ./public

EXPOSE 9292

# Сервер свой (lib/specgen/web/server.rb): в Rack 3 команда `rackup` и
# WEBrick вынесены в отдельные гемы, а нового гема проект не добавляет.
# config.ru при этом рабочий — под любым сторонним Rack-сервером.
CMD ["bundle", "exec", "ruby", "bin/serve"]

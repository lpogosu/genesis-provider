# Образ с генератором: тот же инструмент, что запускается из репозитория,
# только на чистой машине. Одна команда поднимает HTTP-API, другая гоняет
# CLI по всем спецификациям — жюри не нужно ставить Ruby.
#
#   docker build -t specgen .
#   docker run --rm -p 9292:9292 specgen          # веб-API на 9292
#   docker run --rm specgen ./integrate --all     # пакетный прогон в консоли
FROM ruby:3.4-slim

# Ruby печатает и читает UTF-8: заголовки спецификаций и весь наш вывод —
# по-русски, а в slim-образе локаль по умолчанию POSIX.
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Гемы лежат вне /app, поэтому COPY исходников их не затирает.
ENV BUNDLE_PATH=/usr/local/bundle
# В образе приложения нужны только rack и thor: rspec, rubocop и webmock —
# инструменты разработки, в поставке им делать нечего.
ENV BUNDLE_WITHOUT=development:test
# Расхождение Gemfile и Gemfile.lock должно ронять сборку, а не молча
# ставить другую версию.
ENV BUNDLE_FROZEN=1

# Адрес и порт сервера читает bin/serve; порт наружу открыт ниже.
ENV HOST=0.0.0.0
ENV PORT=9292

WORKDIR /app

# Зависимости отдельным слоем: правка исходников не пересобирает bundle.
# Компилятор не ставим намеренно — rack и thor чистые Ruby, нативных
# расширений в поставке нет.
COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

# Права на исполнение: на Windows-хосте бит `x` в индексе git не хранится,
# а запускать нужно и CLI, и сервер.
RUN chmod +x integrate bin/integrate bin/serve

# Сюда встанет сборка фронта, когда появится каталог web/:
#
#   FROM node:22-slim AS front
#   WORKDIR /front
#   COPY web/package*.json ./
#   RUN npm ci
#   COPY web/ ./
#   RUN npm run build
#
# и в этот образ — COPY --from=front /front/dist ./public
# Каталог public/ отдаётся автоматически, если он есть: SpecGen::Web::Static
# проверяет его наличие на каждом запросе, отсутствие ничего не ломает.

EXPOSE 9292

# Сервер свой (lib/specgen/web/server.rb): в Rack 3 команда `rackup` и
# WEBrick вынесены в отдельные гемы, а нового гема проект не добавляет.
# config.ru при этом рабочий — под любым сторонним Rack-сервером.
CMD ["bundle", "exec", "ruby", "bin/serve"]

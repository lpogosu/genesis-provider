# frozen_string_literal: true

# Точка входа для любого Rack-сервера: `rackup`, puma, falcon — что найдётся
# на машине. В самом проекте сервера-гема нет (в Rack 3 rackup и WEBrick
# вынесены в отдельные гемы), поэтому образ и `bin/serve` поднимают то же
# приложение через SpecGen::Web::Server. Приложение одно и то же.
$LOAD_PATH.unshift(File.expand_path('lib', File.dirname(__FILE__)))

require 'specgen'
require 'specgen/web'

run SpecGen::Web.app

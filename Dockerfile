FROM bitwalker/alpine-elixir-phoenix:latest

ENV APP_HOME=/code

WORKDIR /code

RUN mix local.hex --force \
&& mix local.rebar --force

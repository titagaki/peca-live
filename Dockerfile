# syntax=docker/dockerfile:1
FROM ruby:3.4.4-slim AS base

ENV LANG=C.UTF-8 \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development test" \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=1

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends libpq5 curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# --- アセットビルド ---------------------------------------------------------
FROM base AS build

# Node は .node-version に合わせる (webpacker 5)。x86_64 のみ
ARG NODE_VERSION=13.7.0
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential libpq-dev libyaml-dev pkg-config git xz-utils && \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
      | tar -xJ -C /usr/local --strip-components=1 && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf "${BUNDLE_PATH}"/ruby/*/cache

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .
# 本番用アセットを事前ビルド (SECRET_KEY_BASE はビルド時のダミー)
RUN SECRET_KEY_BASE=dummy bundle exec rails assets:precompile && \
    rm -rf node_modules tmp/cache

# --- 実行イメージ -----------------------------------------------------------
FROM base

# development group の gem は入れない。test 用に rspec を動かすときは build ステージを使う
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

RUN useradd -m -s /bin/bash rails && mkdir -p /app/tmp/pids /app/tmp/cache /app/log && chown -R rails:rails /app/tmp /app/log
USER rails

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

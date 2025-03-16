FROM ruby:2.7.1
RUN apt-get update && apt-get install -y \
    nodejs \
    yarn \
    libevent-dev \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean

WORKDIR /app
COPY Gemfile Gemfile.lock /app

RUN bundle install

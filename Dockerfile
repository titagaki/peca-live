FROM ruby:2.7.1

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    libxml2-dev \
    libxslt1-dev \
    curl \
    sqlite3 \
    libsqlite3-dev

RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash -\
  && apt-get install -y nodejs \
  && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -\
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
  && apt-get update \
  && apt-get install -y yarn \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v "2.4.22"
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]

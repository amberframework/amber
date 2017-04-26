FROM drujensen/crystal:0.22.0

ENV KGEN_VERSION 0.3.2

RUN curl -L https://github.com/TechMagister/kemalyst-generator/archive/v$KGEN_VERSION.tar.gz | tar xvz -C /app/. && cd /app/kemalyst-generator-$KGEN_VERSION && crystal deps && make

RUN ln -s /app/kemalyst-generator-$KGEN_VERSION/bin/kgen /usr/local/bin/kgen

WORKDIR /app/user

ADD . /app/user

RUN crystal deps

CMD ["crystal", "spec"]

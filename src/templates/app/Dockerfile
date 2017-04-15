FROM drujensen/crystal:0.21.1

RUN cd /tmp && curl https://codeload.github.com/TechMagister/kemalyst-generator/tar.gz/v0.2.5 | tar xz && cd kemalyst-generator-0.2.5 && crystal deps && make && cp bin/kgen /usr/local/bin/.

WORKDIR /app/user

ADD . /app/user

RUN crystal deps

CMD ["crystal", "spec"]

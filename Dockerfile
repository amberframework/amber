FROM drujensen/crystal:0.22.0-1

WORKDIR /app/user

ADD . /app/user

RUN crystal deps

CMD ["crystal", "spec"]

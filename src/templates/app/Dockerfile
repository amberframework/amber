FROM drujensen/crystal:0.20.0

ADD . /app/user
WORKDIR /app/user

RUN crystal deps

CMD ["crystal", "spec"]


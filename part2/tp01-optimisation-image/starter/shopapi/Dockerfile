# Dockerfile "historique" de l'équipe : ça marche, personne n'a osé y toucher depuis 2021.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update
RUN apt-get install -y curl wget vim git build-essential python3
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
RUN apt-get install -y nodejs
RUN npm install -g nodemon
WORKDIR /app
COPY . /app
RUN npm install
ENV NODE_ENV=development
ENV DATABASE_URL=postgres://shop:S3cret!@db.internal:5432/shop
EXPOSE 3000
CMD npm start

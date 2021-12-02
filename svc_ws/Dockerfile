FROM public.ecr.aws/docker/library/node:14
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install --production
COPY . .
CMD [ "node", "index.js" ]
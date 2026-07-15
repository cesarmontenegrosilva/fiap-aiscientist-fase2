FROM node:20-slim
WORKDIR /workspace
RUN npm install --global @dataform/cli@3.0.26
COPY . .
ENTRYPOINT ["dataform"]
CMD ["run", "."]

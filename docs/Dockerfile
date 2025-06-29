# Stage 1
FROM alpine:3.22.0 AS build

# Install the Hugo go app.
RUN apk --no-cache --update add hugo=0.147.2-r0

WORKDIR /opt/HugoApp

# Copy Hugo config into the container Workdir.
COPY . .

# Run Hugo in the Workdir to generate HTML.
RUN hugo 

# Stage 2
FROM nginx:1.29-alpine3.22 AS final

# Set workdir to the NGINX default dir.
WORKDIR /usr/share/nginx/html

# Copy HTML from previous build into the Workdir.
COPY --from=build /opt/HugoApp/public .

# Expose port 80
EXPOSE 80/tcp

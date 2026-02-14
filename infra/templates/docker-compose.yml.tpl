services:
  n8n:
    image: n8nio/n8n
    container_name: n8n
    restart: always
    ports:
      - "${n8n_port}:5678"
    env_file:
      - .env
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:

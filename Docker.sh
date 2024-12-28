#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}This script requires root access.${NC}"
    exit 1
fi

# Nhập mã ID
echo -e "${YELLOW}Please enter your identity code:${NC}"
read -p "> " id
if [[ -z "$id" ]]; then
    echo -e "${RED}Identity code cannot be empty.${NC}"
    exit 1
fi

# Cài đặt Docker nếu cần
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}Installing Docker...${NC}"
    apt-get update
    apt-get install -y docker.io
else
    echo -e "${GREEN}Docker is already installed.${NC}"
fi

# Lấy danh sách IP công cộng
public_ips=$(curl -s ifconfig.me || hostname -I)

if [ -z "$public_ips" ]; then
    echo -e "${RED}Failed to detect public IP.${NC}"
    exit 1
fi

# Thiết lập thông số
storage_gb=50
start_port=1235
container_count=10  # Tăng số lượng container (mặc định 10)

# Pull Docker image
echo -e "${GREEN}Pulling the Docker image nezha123/titan-edge...${NC}"
docker pull nezha123/titan-edge || { echo -e "${RED}Failed to pull Docker image.${NC}"; exit 1; }

current_port=$start_port

# Cấu hình nodes
for ip in $public_ips; do
    echo -e "${GREEN}Setting up nodes for IP $ip${NC}"
    
    for ((i=1; i<=container_count; i++)); do
        storage_path="/root/titan_storage_${ip}_${i}"
        mkdir -p "$storage_path"

        container_id=$(docker run -d --restart always -v "$storage_path:/root/.titanedge/storage" \
            --name "titan_${ip}_${i}" --net=host nezha123/titan-edge) || {
            echo -e "${RED}Failed to start container for node titan_${ip}_${i}.${NC}"
            continue
        }

        echo -e "${GREEN}Node titan_${ip}_${i} is running with container ID $container_id${NC}"

        sleep 30

        docker exec "$container_id" bash -c "\
            sed -i 's/^#StorageGB = .*/StorageGB = $storage_gb/' /root/.titanedge/config.toml && \
            sed -i 's/^#ListenAddress = \"0.0.0.0:1234\"/ListenAddress = \"0.0.0.0:$current_port\"/' /root/.titanedge/config.toml" || {
            echo -e "${RED}Failed to configure node titan_${ip}_${i}.${NC}"
            continue
        }

        docker restart "$container_id"
        docker exec "$container_id" bash -c "\
            titan-edge bind --hash=$id https://api-test1.container1.titannet.io/api/v2/device/binding" || {
            echo -e "${RED}Failed to bind node titan_${ip}_${i}.${NC}"
        }

        echo -e "${GREEN}Node titan_${ip}_${i} has been bound.${NC}"
        current_port=$((current_port + 1))
    done
done

echo -e "${GREEN}============================== All nodes have been set up and are running ===============================${NC}"

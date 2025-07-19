#!/bin/bash

# Nexus CLI Docker Compose Setup Script
# 플랫폼별 자동 감지 및 다중 노드 설정 지원

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"
NODE_IDS_FILE="$CONFIG_DIR/node-ids.txt"

# Create directories
mkdir -p "$CONFIG_DIR"

# 운영체제 감지
detect_os() {
    echo -e "${BLUE}=== System Detection ===${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        echo -e "${GREEN}✓ Operating System: macOS${NC}"
    elif [[ -f /etc/ubuntu-release ]] || [[ $(uname -a) == *"Ubuntu"* ]]; then
        OS="ubuntu"
        echo -e "${GREEN}✓ Operating System: Ubuntu${NC}"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        echo -e "${GREEN}✓ Operating System: Debian${NC}"
    elif [[ -f /etc/centos-release ]] || [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        echo -e "${GREEN}✓ Operating System: RHEL/CentOS${NC}"
    else
        OS="linux"
        echo -e "${YELLOW}⚠ Operating System: Generic Linux${NC}"
    fi
}

# 아키텍쳐 감지
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64)
            ARCH="amd64"
            DOCKER_PLATFORM="linux/amd64"
            echo -e "${GREEN}✓ Architecture: AMD64/x86_64${NC}"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            DOCKER_PLATFORM="linux/arm64"
            echo -e "${GREEN}✓ Architecture: ARM64/aarch64${NC}"
            ;;
        armv7l)
            ARCH="armv7"
            DOCKER_PLATFORM="linux/arm/v7"
            echo -e "${GREEN}✓ Architecture: ARMv7${NC}"
            ;;
        *)
            echo -e "${RED}✗ Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac
}

# Docker 설치 확인
check_docker() {
    echo -e "\n${BLUE}=== Docker Check ===${NC}"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}✗ Docker not found!${NC}"
        echo -e "${YELLOW}Please install Docker first: https://docs.docker.com/get-docker/${NC}"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${RED}✗ Docker Compose not found!${NC}"
        echo -e "${YELLOW}Please install Docker Compose${NC}"
        exit 1
    fi
    
    # Docker Compose 명령어 결정
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    else
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
    
    echo -e "${GREEN}✓ Docker: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)${NC}"
    echo -e "${GREEN}✓ Docker Compose: Available${NC}"
    
    # Docker 권한 및 daemon 상태 확인
    check_docker_permissions
}

# Docker 권한 문제 해결 가이드
show_docker_permission_fix() {
    local error_type="$1"
    
    echo -e "\n${RED}=== Docker 권한 문제 해결 방법 ===${NC}"
    
    case "$error_type" in
        "permission_denied")
            echo -e "${YELLOW}권한 거부 문제가 발생했습니다.${NC}\n"
            
            if [[ "$OS" == "macos" ]]; then
                echo -e "${CYAN}macOS 해결책:${NC}"
                echo -e "1. Docker Desktop을 재시작해주세요:"
                echo -e "   ${GREEN}Docker Desktop → Quit Docker Desktop → 다시 실행${NC}"
                echo -e "2. Docker Desktop 설정에서 권한을 확인해주세요"
            else
                echo -e "${CYAN}Linux 해결책:${NC}"
                echo -e "1. 현재 사용자를 docker 그룹에 추가:"
                echo -e "   ${GREEN}sudo usermod -aG docker \$USER${NC}"
                echo -e "   ${GREEN}newgrp docker${NC}"
                echo -e "2. 또는 sudo로 실행:"
                echo -e "   ${GREEN}sudo ./nexus_bootstap.sh${NC}"
                echo -e "3. Docker daemon 시작 확인:"
                echo -e "   ${GREEN}sudo systemctl start docker${NC}"
                echo -e "   ${GREEN}sudo systemctl enable docker${NC}"
            fi
            ;;
        "daemon_not_running")
            echo -e "${YELLOW}Docker daemon이 실행되지 않고 있습니다.${NC}\n"
            
            if [[ "$OS" == "macos" ]]; then
                echo -e "${CYAN}macOS 해결책:${NC}"
                echo -e "1. Docker Desktop을 시작해주세요:"
                echo -e "   Applications → Docker.app 실행"
                echo -e "2. 시스템 트레이에서 Docker 아이콘이 나타날 때까지 기다려주세요"
            else
                echo -e "${CYAN}Linux 해결책:${NC}"
                echo -e "1. Docker daemon 시작:"
                echo -e "   ${GREEN}sudo systemctl start docker${NC}"
                echo -e "2. 자동 시작 설정:"
                echo -e "   ${GREEN}sudo systemctl enable docker${NC}"
                echo -e "3. 상태 확인:"
                echo -e "   ${GREEN}sudo systemctl status docker${NC}"
            fi
            ;;
    esac
    
    echo -e "\n${PURPLE}해결 후 다시 스크립트를 실행해주세요.${NC}"
}

# Docker 권한 및 상태 확인
check_docker_permissions() {
    echo -e "\n${BLUE}=== Docker 권한 및 상태 확인 ===${NC}"
    
    # Docker daemon 접근 테스트
    local docker_test_output
    local docker_test_exit_code
    
    docker_test_output=$(docker info 2>&1)
    docker_test_exit_code=$?
    
    if [[ $docker_test_exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ Docker daemon 접근 성공${NC}"
        echo -e "${GREEN}✓ Docker 권한 문제 없음${NC}"
    else
        echo -e "${RED}✗ Docker 접근 실패${NC}"
        
        # 에러 타입 분석
        if echo "$docker_test_output" | grep -q "permission denied\|Permission denied"; then
            echo -e "${RED}✗ 권한 거부 오류 감지${NC}"
            show_docker_permission_fix "permission_denied"
            exit 1
        elif echo "$docker_test_output" | grep -q "Cannot connect to the Docker daemon\|Is the docker daemon running"; then
            echo -e "${RED}✗ Docker daemon이 실행되지 않음${NC}"
            show_docker_permission_fix "daemon_not_running"
            exit 1
        elif echo "$docker_test_output" | grep -q "dial unix.*connect: no such file or directory"; then
            echo -e "${RED}✗ Docker socket 연결 실패${NC}"
            show_docker_permission_fix "daemon_not_running"
            exit 1
        else
            echo -e "${RED}✗ 알 수 없는 Docker 오류:${NC}"
            echo -e "${YELLOW}$docker_test_output${NC}"
            echo -e "\n${PURPLE}수동으로 Docker 상태를 확인해주세요:${NC}"
            echo -e "${GREEN}docker --version && docker info${NC}"
            exit 1
        fi
    fi
    
    # Docker 컨테이너 실행 테스트
    echo -e "${CYAN}Docker 컨테이너 실행 테스트 중...${NC}"
    if docker run --rm hello-world &> /dev/null; then
        echo -e "${GREEN}✓ Docker 컨테이너 실행 성공${NC}"
    else
        echo -e "${YELLOW}⚠ Docker 컨테이너 실행 테스트 실패 (네트워크 문제일 수 있음)${NC}"
    fi
}

# 시스템 리소스 확인
check_system_resources() {
    echo -e "\n${BLUE}=== System Resources ===${NC}"
    
    # CPU 코어 수
    if [[ "$OS" == "macos" ]]; then
        TOTAL_CORES=$(sysctl -n hw.ncpu)
        TOTAL_MEMORY_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    else
        TOTAL_CORES=$(nproc)
        TOTAL_MEMORY_GB=$(( $(free -m | awk 'NR==2{print $2}') / 1024 ))
    fi
    
    echo -e "${CYAN}CPU Cores: ${TOTAL_CORES}${NC}"
    echo -e "${CYAN}Total Memory: ${TOTAL_MEMORY_GB}GB${NC}"
    
    # Docker 메모리 제한 확인
    if [[ "$OS" == "macos" ]]; then
        echo -e "${YELLOW}⚠ On macOS, ensure Docker Desktop has sufficient memory allocation${NC}"
        echo -e "${YELLOW}  Recommended: At least 8GB for Docker Desktop${NC}"
    fi
}

# NodeID 입력 받기
collect_node_ids() {
    local node_count=$1
    local nodeids=()
    
    echo -e "\n${PURPLE}=== Node ID Configuration ===${NC}"
    echo -e "${CYAN}You can:${NC}"
    echo -e "${CYAN}1) Enter Node IDs manually${NC}"
    echo -e "${CYAN}2) Load from file (one per line)${NC}"
    
    read -p "Select option (1/2): " input_method
    
    case $input_method in
        1)
            echo -e "\n${YELLOW}Enter $node_count Node IDs:${NC}"
            for i in $(seq 1 $node_count); do
                while true; do
                    read -p "Node ID $i: " nodeid
                    if [[ -n "$nodeid" && "$nodeid" =~ ^[a-zA-Z0-9]+$ ]]; then
                        nodeids+=("$nodeid")
                        break
                    else
                        echo -e "${RED}Invalid Node ID! Use only alphanumeric characters.${NC}"
                    fi
                done
            done
            ;;
        2)
            read -p "Enter file path: " filepath
            if [[ -f "$filepath" ]]; then
                while IFS= read -r line && [[ ${#nodeids[@]} -lt $node_count ]]; do
                    line=$(echo "$line" | xargs) # trim whitespace
                    if [[ -n "$line" && "$line" =~ ^[a-zA-Z0-9]+$ ]]; then
                        nodeids+=("$line")
                    fi
                done < "$filepath"
                
                if [[ ${#nodeids[@]} -lt $node_count ]]; then
                    echo -e "${RED}Not enough valid Node IDs in file! Found: ${#nodeids[@]}, Need: $node_count${NC}"
                    return 1
                fi
                echo -e "${GREEN}✓ Loaded ${#nodeids[@]} Node IDs from file${NC}"
            else
                echo -e "${RED}File not found: $filepath${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}Invalid option!${NC}"
            return 1
            ;;
    esac
    
    # Save Node IDs to file
    printf "%s\n" "${nodeids[@]}" > "$NODE_IDS_FILE"
    echo -e "${GREEN}✓ Node IDs saved to: $NODE_IDS_FILE${NC}"
    
    # Export for use in docker-compose
    NODE_IDS=("${nodeids[@]}")
}

# Dockerfile 생성
create_dockerfile() {
    echo -e "\n${BLUE}=== Creating Dockerfile ===${NC}"
    
    cat > "$SCRIPT_DIR/Dockerfile" << EOF
FROM alpine:3.22.0

# Install dependencies
RUN apk update && \\
    apk add --no-cache curl bash && \\
    curl -sSf https://cli.nexus.xyz/ -o install.sh && \\
    chmod +x install.sh && \\
    NONINTERACTIVE=1 ./install.sh && \\
    rm -f install.sh

# Create nexus user for better security
RUN adduser -D -s /bin/bash nexus && \\
    mkdir -p /home/nexus/.nexus && \\
    chown -R nexus:nexus /home/nexus

USER nexus
WORKDIR /home/nexus

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \\
    CMD pgrep nexus-cli || exit 1

ENTRYPOINT ["/root/.nexus/bin/nexus-cli"]
EOF
    
    echo -e "${GREEN}✓ Dockerfile created${NC}"
}

# Docker Compose 파일 생성
create_docker_compose() {
    local node_count=$1
    local memory_limit="5g"
    local cpu_limit="2.0"
    
    echo -e "\n${BLUE}=== Creating Docker Compose Configuration ===${NC}"
    
    # Calculate resource allocation per node
    local memory_per_node_mb=$((2 * 1024))  # 2GB per node
    local cpu_per_node=$(echo "scale=2; 2.0 / $node_count" | bc -l 2>/dev/null || echo "0.5")
    
    cat > "$COMPOSE_FILE" << EOF
version: '3.8'

services:
EOF

    # Generate service for each node
    for i in $(seq 1 $node_count); do
        local node_id=${NODE_IDS[$((i-1))]}
        
        cat >> "$COMPOSE_FILE" << EOF
  nexus-node-$i:
    build:
      context: .
      platforms:
        - $DOCKER_PLATFORM
    platform: $DOCKER_PLATFORM
    container_name: nexus-node-$i
    hostname: nexus-node-$i
    command: ["start", "--headless", "--node-id", "$node_id"]
    environment:
      - NODE_ID=$node_id
      - NODE_NUMBER=$i
      - RUST_LOG=info
    deploy:
      resources:
        limits:
          memory: ${memory_per_node_mb}m
          cpus: '$cpu_per_node'
        reservations:
          memory: $((memory_per_node_mb / 4))m
          cpus: '0.1'
    restart: unless-stopped
    networks:
      - nexus-network
    volumes:
      - nexus-node-$i-data:/home/nexus/.nexus
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    labels:
      - "nexus.node.id=$node_id"
      - "nexus.node.number=$i"

EOF
    done
    
    # Add networks and volumes
    cat >> "$COMPOSE_FILE" << EOF

networks:
  nexus-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
EOF
    
    for i in $(seq 1 $node_count); do
        echo "  nexus-node-$i-data:" >> "$COMPOSE_FILE"
    done
    
    echo -e "${GREEN}✓ Docker Compose file created${NC}"
    echo -e "${CYAN}  Nodes: $node_count${NC}"
    echo -e "${CYAN}  Memory per node: ${memory_per_node_mb}MB${NC}"
    echo -e "${CYAN}  CPU per node: $cpu_per_node cores${NC}"
}

# 환경 파일 생성
create_env_file() {
    echo -e "\n${BLUE}=== Creating Environment Configuration ===${NC}"
    
    cat > "$ENV_FILE" << EOF
# Nexus Docker Configuration
COMPOSE_PROJECT_NAME=nexus-cluster
DOCKER_PLATFORM=$DOCKER_PLATFORM
NODE_COUNT=${#NODE_IDS[@]}
TOTAL_MEMORY_LIMIT=$((${#NODE_IDS[@]} * 2))g
TOTAL_CPU_LIMIT=2.0

# System Information
DETECTED_OS=$OS
DETECTED_ARCH=$ARCH
SCRIPT_VERSION=1.0.0
CREATED_AT=$(date -Iseconds)
EOF
    
    echo -e "${GREEN}✓ Environment file created${NC}"
}

# Docker Compose 관리 명령어들
start_services() {
    echo -e "\n${BLUE}=== Starting Nexus Services ===${NC}"
    
    cd "$SCRIPT_DIR" || exit 1
    
    echo -e "${YELLOW}Building images...${NC}"
    $DOCKER_COMPOSE_CMD build --parallel
    
    echo -e "${YELLOW}Starting services...${NC}"
    $DOCKER_COMPOSE_CMD up -d
    
    echo -e "${GREEN}✓ Services started successfully${NC}"
    
    # Wait a moment and check status
    sleep 5
    check_status
}

stop_services() {
    echo -e "\n${BLUE}=== Stopping Nexus Services ===${NC}"
    
    cd "$SCRIPT_DIR" || exit 1
    $DOCKER_COMPOSE_CMD down
    
    echo -e "${GREEN}✓ Services stopped${NC}"
}

check_status() {
    echo -e "\n${BLUE}=== Service Status ===${NC}"
    
    cd "$SCRIPT_DIR" || exit 1
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        echo -e "${RED}✗ Docker Compose file not found${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Container Status:${NC}"
    $DOCKER_COMPOSE_CMD ps
    
    echo -e "\n${CYAN}Resource Usage:${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker ps --filter "label=com.docker.compose.project=nexus-cluster" -q) 2>/dev/null || echo "No running containers"
}

show_logs() {
    echo -e "\n${BLUE}=== Service Logs ===${NC}"
    
    cd "$SCRIPT_DIR" || exit 1
    
    if [[ -n "$1" ]]; then
        echo -e "${CYAN}Logs for service: $1${NC}"
        $DOCKER_COMPOSE_CMD logs -f "$1"
    else
        echo -e "${CYAN}All service logs:${NC}"
        $DOCKER_COMPOSE_CMD logs -f
    fi
}

# 설정 검증
validate_config() {
    local node_count=$1
    
    echo -e "\n${BLUE}=== Configuration Validation ===${NC}"
    
    # Node count validation
    if [[ $node_count -lt 1 || $node_count -gt 20 ]]; then
        echo -e "${RED}✗ Invalid node count: $node_count (must be 1-20)${NC}"
        return 1
    fi
    
    # Memory validation (2GB per node)
    local memory_per_node_mb=$((2 * 1024))
    local total_memory_required=$((memory_per_node_mb * node_count))
    echo -e "${CYAN}Memory allocation: 2GB per node${NC}"
    echo -e "${CYAN}Total memory required: $((total_memory_required / 1024))GB${NC}"
    
    # Check if bc is available for CPU calculation
    if ! command -v bc &> /dev/null && [[ $node_count -gt 4 ]]; then
        echo -e "${YELLOW}⚠ 'bc' calculator not found - CPU limits may be approximated${NC}"
    fi
    
    echo -e "${GREEN}✓ Configuration validated${NC}"
    return 0
}

# 메인 설정 마법사
main_wizard() {
    echo -e "\n${PURPLE}=== Nexus Docker Setup Wizard ===${NC}"
    
    # Get node count
    while true; do
        read -p "How many Nexus nodes do you want to run? (1-20): " node_count
        if [[ "$node_count" =~ ^[1-9]$|^1[0-9]$|^20$ ]]; then
            break
        else
            echo -e "${RED}Invalid input! Please enter a number between 1-20.${NC}"
        fi
    done
    
    # Validate configuration
    if ! validate_config "$node_count"; then
        return 1
    fi
    
    # Collect Node IDs
    if ! collect_node_ids "$node_count"; then
        return 1
    fi
    
    # Show configuration summary
    echo -e "\n${PURPLE}=== Configuration Summary ===${NC}"
    echo -e "${CYAN}Platform: $OS ($ARCH) - $DOCKER_PLATFORM${NC}"
    echo -e "${CYAN}Node Count: $node_count${NC}"
    echo -e "${CYAN}Memory per node: 2GB${NC}"
    echo -e "${CYAN}Total Memory Required: $((node_count * 2))GB${NC}"
    echo -e "${CYAN}Total CPU: 2.0 cores${NC}"
    
    echo -e "\n${CYAN}Node IDs:${NC}"
    for i in "${!NODE_IDS[@]}"; do
        echo -e "  Node $((i+1)): ${NODE_IDS[i]}"
    done
    
    read -p "Proceed with this configuration? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${YELLOW}Setup cancelled${NC}"
        return 1
    fi
    
    # Create configuration files
    create_dockerfile
    create_docker_compose "$node_count"
    create_env_file
    
    echo -e "\n${GREEN}✓ Setup completed successfully!${NC}"
    echo -e "${CYAN}Files created:${NC}"
    echo -e "  - Dockerfile"
    echo -e "  - docker-compose.yml"
    echo -e "  - .env"
    echo -e "  - config/node-ids.txt"
    
    # Ask if user wants to start services
    echo -e "\n${YELLOW}Do you want to start the services now? (y/n):${NC}"
    read -p "" start_now
    if [[ "$start_now" == "y" ]]; then
        start_services
    else
        echo -e "${CYAN}To start services later, run: ${YELLOW}$0 start${NC}"
    fi
}

# 메뉴 시스템
show_menu() {
    echo -e "\n${PURPLE}=== Nexus Docker Manager ===${NC}"
    echo -e "${CYAN}Platform: $OS ($ARCH) - $DOCKER_PLATFORM${NC}"
    echo ""
    echo -e "${CYAN}1) Setup new configuration${NC}"
    echo -e "${CYAN}2) Start services${NC}"
    echo -e "${CYAN}3) Stop services${NC}"
    echo -e "${CYAN}4) Check status${NC}"
    echo -e "${CYAN}5) Show logs${NC}"
    echo -e "${CYAN}6) Restart services${NC}"
    echo -e "${CYAN}7) Clean up (remove containers & images)${NC}"
    echo -e "${CYAN}0) Exit${NC}"
}

# 정리 함수
cleanup() {
    echo -e "\n${YELLOW}=== Cleanup ===${NC}"
    
    cd "$SCRIPT_DIR" || exit 1
    
    echo -e "${YELLOW}Stopping and removing containers...${NC}"
    $DOCKER_COMPOSE_CMD down -v --rmi local --remove-orphans
    
    echo -e "${YELLOW}Removing unused Docker resources...${NC}"
    docker system prune -f
    
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# 메인 실행 부분
main() {
    # 시스템 감지
    detect_os
    detect_arch
    check_docker
    check_system_resources
    
    # 명령줄 인자 처리
    case "${1:-menu}" in
        setup|wizard)
            main_wizard
            ;;
        start)
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            stop_services
            sleep 2
            start_services
            ;;
        status)
            check_status
            ;;
        logs)
            show_logs "$2"
            ;;
        cleanup|clean)
            cleanup
            ;;
        menu|*)
            # Interactive menu
            while true; do
                show_menu
                read -p "Select option: " option
                
                case $option in
                    1) main_wizard ;;
                    2) start_services ;;
                    3) stop_services ;;
                    4) check_status ;;
                    5) 
                        echo -e "${CYAN}Show logs for specific service? (press Enter for all):${NC}"
                        read -p "Service name: " service_name
                        show_logs "$service_name"
                        ;;
                    6) 
                        stop_services
                        sleep 2
                        start_services
                        ;;
                    7) cleanup ;;
                    0)
                        echo -e "${GREEN}Goodbye!${NC}"
                        exit 0
                        ;;
                    *) echo -e "${RED}Invalid option!${NC}" ;;
                esac
                
                if [[ $option != 5 ]]; then
                    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
                    read
                fi
            done
            ;;
    esac
}

# 스크립트가 직접 실행될 때만 main 함수 호출
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
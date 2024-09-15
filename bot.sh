#!/bin/bash

Crontab_file="/usr/bin/crontab"
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m"
Font_color_suffix="\033[0m"
Info="[${Green_font_prefix}INFO${Font_color_suffix}]"
Error="[${Red_font_prefix}ERROR${Font_color_suffix}]"
Tip="[${Green_font_prefix}NOTE${Font_color_suffix}]"

# Eğer $1 parametresi verilmediyse, kullanıcıdan giriş iste
if [ -z "$1" ]; then
    echo -e "${Green_font_prefix}Mevcut Seçenekler:${Font_color_suffix}"
    echo "1) Ortamı Kur ve Tam Düğümü Yükle"
    echo "2) Yeni Cüzdan Oluştur"
    echo "3) Cüzdan Bakiyesini Kontrol Et"
    echo "4) CAT Token Bas"
    echo "5) Düğüm Loglarını Kontrol Et"
    echo "6) Token Gönder"
    echo "7) Cüzdanı Kurtar (Recovery)"
    read -e -p "Lütfen bir seçenek girin: " num
else
    num="$1"
fi

# ROOT kullanıcısı olup olmadığını kontrol eder
check_root() {
    if [[ $EUID != 0 ]]; then
        echo -e "${Error} ROOT kullanıcısı değilsiniz. ROOT olarak devam etmek için ${Green_background_prefix}sudo su${Font_color_suffix} komutunu kullanabilirsiniz."
        exit 1
    fi
}

# Ortamı kurar ve tam düğümü yükler
install_env_and_full_node() {
    check_root
    sudo apt update && sudo apt upgrade -y
    sudo apt install curl tar wget clang pkg-config libssl-dev jq build-essential git make docker.io -y
    VERSION=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*\d')
    DESTINATION=/usr/local/bin/docker-compose
    sudo curl -L https://github.com/docker/compose/releases/download/${VERSION}/docker-compose-$(uname -s)-$(uname -m) -o $DESTINATION
    sudo chmod 755 $DESTINATION

    sudo apt-get install npm -y
    sudo npm install n -g
    sudo n stable
    sudo npm i -g yarn

    git clone https://github.com/CATProtocol/cat-token-box
    cd cat-token-box
    sudo yarn install
    sudo yarn build

    MAX_CPUS=$(nproc)
    MAX_MEMORY=$(free -m | awk '/Mem:/ {print int($2*0.8)"M"}')

    cd ./packages/tracker/
    sudo chmod 777 docker/data
    sudo chmod 777 docker/pgdata
    sudo docker-compose up -d

    cd ../../
    sudo docker build -t tracker:latest .
    sudo docker run -d \
        --name tracker \
        --cpus="$MAX_CPUS" \
        --memory="$MAX_MEMORY" \
        --add-host="host.docker.internal:host-gateway" \
        -e DATABASE_HOST="host.docker.internal" \
        -e RPC_HOST="host.docker.internal" \
        -p 3000:3000 \
        tracker:latest
    echo '{
      "network": "fractal-mainnet",
      "tracker": "http://127.0.0.1:3000",
      "dataDir": ".",
      "maxFeeRate": 30,
      "rpc": {
          "url": "http://127.0.0.1:8332",
          "username": "bitcoin",
          "password": "opcatAwesome"
      }
    }' > ~/cat-token-box/packages/cli/config.json
}

# Cüzdan oluşturur, mevcut cüzdanı siler, sadece mnemonik ve adresi print eder ve kaydeder
create_wallet() {
  echo -e "\n"
  cd ~/cat-token-box/packages/cli
  
  # Mevcut cüzdan dosyasını sil
  rm -rf wallet.json
  
  # Cüzdan oluşturma ve yakalama
  WALLET_OUTPUT=$(sudo yarn cli wallet create 2>&1)
  ADDRESS_OUTPUT=$(sudo yarn cli wallet address 2>&1)
  
  # Kurtarma cümlesini ve adresi yakalama
  MNEMONIC=$(echo "$WALLET_OUTPUT" | grep "Your wallet mnemonic is" | sed 's/Your wallet mnemonic is: //')
  ADDRESS=$(echo "$ADDRESS_OUTPUT" | grep "Your address is" | sed 's/Your address is //')
  
  # Terminalde sadece mnemonik ve adresi göster
  echo -e "Cüzdan Kurtarma Cümlesi: $MNEMONIC"
  echo -e "Cüzdan Adresi: $ADDRESS"
  
  # Cüzdan ve adres bilgilerini data.txt'ye kaydet
  echo "### Yeni Cüzdan ###" >> ~/data.txt
  echo "Cüzdan Kurtarma Cümlesi: $MNEMONIC" >> ~/data.txt
  echo "Cüzdan Adresi: $ADDRESS" >> ~/data.txt
  
  echo -e "\nCüzdan adresi ve kurtarma cümlesi 'data.txt' dosyasına kaydedildi."
}

recover_wallet() {
    echo -e "\nCüzdanı kurtarmak için 12 kelimelik kurtarma cümlenizi girin:"
    read -p "Kurtarma Cümlesi: " mnemonic

    # mnemonic değerini wallet.json'a güncelle
    jq --arg mnemonic "$mnemonic" '.mnemonic = $mnemonic' ~/cat-token-box/packages/cli/wallet.json > ~/cat-token-box/packages/cli/wallet_temp.json && mv ~/cat-token-box/packages/cli/wallet_temp.json ~/cat-token-box/packages/cli/wallet.json

    echo -e "\nWallet recovery için wallet.json dosyasındaki mnemonic güncellendi."

    # Cüzdanı export et
    cd ~/cat-token-box/packages/cli
    sudo yarn cli wallet export

    # Adresi göster
    sudo yarn cli wallet address
}

# CAT token basma işlemi (parametreli)
start_mint_cat() {
  tokenId="$2"
  newMaxFeeRate="$3"
  amount="$4"

  # MaxFeeRate'i config dosyasına ekle
  sed -i "s/\"maxFeeRate\": [0-9]*/\"maxFeeRate\": $newMaxFeeRate/" ~/cat-token-box/packages/cli/config.json

  cd ~/cat-token-box/packages/cli
  command="sudo yarn cli mint -i $tokenId $amount"

  while true; do
      $command

      if [ $? -ne 0 ]; then
          echo "Komut çalıştırılamadı, çıkılıyor."
          exit 1
      fi

      sleep 1
  done
}

# Düğüm loglarını kontrol eder
check_node_log() {
  docker logs -f --tail 100 tracker
}

# Cüzdan bakiyesini kontrol eder
check_wallet_balance() {
  cd ~/cat-token-box/packages/cli
  sudo yarn cli wallet balances
}

# Token gönderir
send_token() {
  read -p "Lütfen tokenId'yi girin: " tokenId
  read -p "Lütfen alıcının adresini girin: " receiver
  read -p "Lütfen gönderilecek miktarı girin: " amount
  cd ~/cat-token-box/packages/cli
  sudo yarn cli send -i $tokenId $receiver $amount
  if [ $? -eq 0 ]; then
      echo -e "${Info} Transfer başarılı"
  else
      echo -e "${Error} Transfer başarısız. Lütfen tekrar deneyin."
  fi
}

# Menü
case "$num" in
    1)
        install_env_and_full_node
        ;;
    2)
        create_wallet
        ;;
    3)
        check_wallet_balance
        ;;
    4)
        start_mint_cat "$@"
        ;;
    5)
        check_node_log
        ;;
    6)
        send_token
        ;;
    7)
        recover_wallet  # Yeni kurtarma seçeneği
        ;;
    *)
        echo -e "${Error} Geçersiz seçenek, lütfen doğru bir numara girin."
        ;;
esac

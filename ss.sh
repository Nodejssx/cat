Crontab_file="/usr/bin/crontab"
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m"
Font_color_suffix="\033[0m"
Info="[${Green_font_prefix}信息${Font_color_suffix}]"
Error="[${Red_font_prefix}错误${Font_color_suffix}]"
Tip="[${Green_font_prefix}注意${Font_color_suffix}]"
if [ -z "$1" ]; then
    read -e -p "Lütfen bir seçenek girin:" num
fi
#ROOT kullanıcısı olup olmadığını kontrol eder, ROOT değilse uyarı verir ve işlemi durdurur
check_root() {
    [[ $EUID != 0 ]] && echo -e "${Error} Şu an ROOT hesabında değilsiniz (veya ROOT yetkiniz yok), işlem devam edemez. Lütfen ROOT hesabına geçiş yapın veya ${Green_background_prefix}sudo su${Font_color_suffix} komutuyla geçici ROOT yetkisi alın (komut girildikten sonra mevcut hesabın şifresi sorulabilir)." && exit 1
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

    MAX_CPUS=$(nproc) # Maksimum işlemci sayısını alır
    MAX_MEMORY=$(free -m | awk '/Mem:/ {print int($2*0.8)"M"}') # Maksimum bellek miktarını hesaplar

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

# Yeni bir cüzdan oluşturur
create_wallet() {
  echo -e "\n"
  cd ~/cat-token-box/packages/cli
  sudo yarn cli wallet create
  echo -e "\n"
  sudo yarn cli wallet address
  echo -e "Lütfen yukarıda oluşturulan cüzdan adresini ve kurtarma cümlesini saklayın"
}

# CAT token basma işlemini başlatır
start_mint_cat() {
  # Token ID'sini girin
  read -p "Lütfen mint yapmak istediğiniz tokenId'yi girin: " tokenId

  # Gas (maxFeeRate) miktarını ayarlayın
  read -p "Lütfen mint için gas ayarlayın: " newMaxFeeRate
  sed -i "s/\"maxFeeRate\": [0-9]*/\"maxFeeRate\": $newMaxFeeRate/" ~/cat-token-box/packages/cli/config.json

  # Mint miktarını girin
  read -p "Lütfen mint yapılacak miktarı girin: " amount

  cd ~/cat-token-box/packages/cli

  # Mint komutunu tokenId ve miktarla güncelle
  command="sudo yarn cli mint -i $tokenId $amount"

  # Mint döngüsünü başlat
  while true; do
      $command

      if [ $? -ne 0 ]; then
          echo "Komut çalıştırılamadı, döngüden çıkılıyor"
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
  read -p "Lütfen tokenId'yi (token adı değil) girin: " tokenId
  read -p "Lütfen alıcının adresini girin: " receiver
  read -p "Lütfen gönderilecek miktarı girin: " amount
  cd ~/cat-token-box/packages/cli
  sudo yarn cli send -i $tokenId $receiver $amount
  if [ $? -eq 0 ]; then
      echo -e "${Info} Transfer başarılı"
  else
      echo -e "${Error} Transfer başarısız, bilgileri kontrol edip tekrar deneyin"
  fi
}


# Menü açıklamaları
echo && echo -e " ${Red_font_prefix}dusk_network tek tıklamayla kurulum betiği${Font_color_suffix} by \033[1;35moooooyoung\033[0m
Bu betik tamamen ücretsizdir ve Twitter kullanıcısı ${Green_font_prefix}@ouyoung11 tarafından geliştirilmiştir${Font_color_suffix}, 
takip etmeyi unutmayın, ücretli bir teklif alırsanız dolandırılmayın.
 ———————————————————————
 ${Green_font_prefix} 1. Ortamı ve tam düğümü kur ${Font_color_suffix}
 ${Green_font_prefix} 2. Cüzdan oluştur ${Font_color_suffix}
 ${Green_font_prefix} 3. Cüzdan bakiyesini kontrol et ${Font_color_suffix}
 ${Green_font_prefix} 4. CAT20 token basmaya başla ${Font_color_suffix}
 ${Green_font_prefix} 5. Düğüm senkronizasyon loglarını kontrol et ${Font_color_suffix}
 ${Green_font_prefix} 6. CAT20 token transfer et ${Font_color_suffix}
 ———————————————————————" && echo

# Este perfil roda POR SSH na maquina. Ele responde a uma pergunta so:
# "o que o playbook disse que fez esta mesmo la?"
#
# Aplicar sem verificar e o modo classico de descobrir, dentro da rede fechada,
# que o servico nem subiu.

versao_singbox = input('versao_singbox')
porta_websocket = input('porta_websocket')

control 'singbox-01' do
  impact 1.0
  title 'O binario e a versao fixada no repositorio'
  desc 'Versao diferente da que o `sing-box check` validou aqui significa que a config foi aprovada por um binario e executada por outro.'

  describe command('/usr/local/bin/sing-box version') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match(/sing-box version #{Regexp.escape(versao_singbox)}/) }
  end
end

control 'singbox-02' do
  impact 1.0
  title 'O servico esta habilitado e rodando'

  describe systemd_service('sing-box') do
    it { should be_installed }
    it { should be_enabled }
    it { should be_running }
  end
end

control 'singbox-03' do
  impact 1.0
  title 'A 443 e do nginx; o sing-box escuta so em loopback'
  desc <<~DESC
    Quem atende a internet na 443/tcp e o demultiplexador, que decide pelo SNI
    entre REALITY e WebSocket. O sing-box fica atras dele, em 127.0.0.1.

    O Hysteria2 e a excecao: e UDP, o nginx nao entra no caminho, e ele escuta
    direto na 443/udp.

    Se o sing-box voltasse a escutar a 443/tcp, os dois disputariam a porta e
    quem perdesse simplesmente nao subiria.
  DESC

  describe port(443).where { protocol =~ /tcp/ } do
    it { should be_listening }
    its('processes') { should include 'nginx' }
  end

  describe port(443).where { protocol =~ /udp/ } do
    it { should be_listening }
  end

  describe port(8444).where { protocol =~ /tcp/ } do
    it { should be_listening }
    its('addresses') { should include '127.0.0.1' }
  end

  describe port(porta_websocket).where { protocol =~ /tcp/ } do
    it { should be_listening }
    its('addresses') { should include '127.0.0.1' }
  end
end

control 'demux-01' do
  impact 1.0
  title 'O demultiplexador esta de pe e com a configuracao valida'

  describe systemd_service('nginx') do
    it { should be_installed }
    it { should be_enabled }
    it { should be_running }
  end

  describe command('nginx -t') do
    its('exit_status') { should eq 0 }
  end

  describe file('/etc/nginx/nginx.conf') do
    its('content') { should match(/ssl_preread on/) }
    its('content') { should match(%r{include /usr/share/nginx/modules/\*\.conf}) }
  end
end

control 'singbox-04' do
  impact 1.0
  title 'O processo nao roda como root'
  desc 'A 443 e porta privilegiada, mas o processo ganha so CAP_NET_BIND_SERVICE. Um servico exposto a internet inteira rodando como root nao tem desculpa.'

  describe processes('sing-box') do
    its('users') { should include 'sing-box' }
    its('users') { should_not include 'root' }
  end
end

control 'singbox-05' do
  impact 1.0
  title 'Configuracao e chave privada nao sao legiveis por qualquer um'
  desc 'A config carrega a chave privada REALITY, o UUID e a auth key do Tailscale. Legivel por todos equivale a publicada.'

  describe file('/etc/sing-box/config.json') do
    it { should exist }
    its('owner') { should eq 'root' }
    its('group') { should eq 'sing-box' }
    it { should_not be_readable.by('other') }
  end

  describe file('/etc/sing-box/tls/key.pem') do
    it { should exist }
    it { should_not be_readable.by('other') }
  end
end

control 'singbox-06' do
  impact 0.7
  title 'A configuracao em uso passa no proprio validador do sing-box'
  desc 'O playbook valida ANTES de instalar; isto confere que o que esta la agora continua valido — inclusive depois de alguem "so ajustar uma coisinha" a mao.'

  describe command('/usr/local/bin/sing-box check -c /etc/sing-box/config.json') do
    its('exit_status') { should eq 0 }
  end
end

control 'rede-01' do
  impact 0.5
  title 'BBR e os buffers de UDP estao ativos'
  desc 'Sem os buffers, o proprio sing-box registra que nao conseguiu aumentar o buffer de recepcao e o Hysteria2 rende muito abaixo do enlace. Sem BBR, o caminho longo com perda rende uma fracao do que poderia.'

  describe kernel_parameter('net.ipv4.tcp_congestion_control') do
    its('value') { should eq 'bbr' }
  end

  describe kernel_parameter('net.core.rmem_max') do
    its('value') { should cmp >= 16777216 }
  end
end

control 'tailnet-01' do
  impact 0.5
  title 'O endpoint Tailscale subiu sem erro'
  desc 'A tailnet e o bonus: sem ela o tunel funciona, mas os outros aparelhos do Rafael ficam inalcancaveis. Falha aqui nao derruba o servico principal, por isso impacto medio.'

  describe command('journalctl -u sing-box --no-pager -n 200') do
    its('stdout') { should_not match(/tailscale.*(FATAL|failed to start)/i) }
  end
end

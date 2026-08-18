# Este perfil roda LOCALMENTE e sonda a maquina pela internet, do jeito que um
# firewall com inspecao profunda sondaria.
#
# E o unico teste que mede o que realmente importa aqui. Um servico de pe com
# todas as portas certas nao vale nada se, ao ser sondado, ele se identificar.
# "As portas estao abertas" e o perfil do servidor; "o disfarce se sustenta" e
# este.

ip = input('ip')
decoy = input('decoy')
dominio = input('dominio')
porta_websocket = input('porta_websocket')

# ⚠️ Isto e uma LAMBDA, e nao um `def`.
#
# Metodo definido no topo de um arquivo de controle NAO fica visivel dentro do
# bloco `control do ... end`: o InSpec avalia o bloco no contexto de um
# Inspec::Rule, e o erro que aparece e
# "undefined method 's_client' for #<Inspec::Rule>", reportado como
# "Control Source Code Error" — que parece erro de sintaxe do arquivo inteiro.
#
# Uma lambda guardada numa constante e capturada pelo closure e funciona.
S_CLIENT = lambda do |destino, sni|
  "echo | timeout 15 openssl s_client -connect #{destino} -servername #{sni} " \
  "-verify_return_error 2>&1"
end

control 'disfarce-01' do
  impact 1.0
  title 'Sondado com o SNI do decoy, o servidor apresenta o certificado do decoy'
  desc <<~DESC
    Esta e A sonda. Um firewall que desconfie da 443 abre a mesma conexao e olha
    o certificado. Com o REALITY funcionando, ele recebe o certificado REAL do
    site decoy, emitido por uma CA publica, valido — e conclui que ali mora um
    site comum.

    Se este controle falhar, o tunel provavelmente ainda transporta dados, e e
    justamente por isso que ele e perigoso: funcionaria nos testes e seria
    identificado na rede que importa.
  DESC

  describe command(S_CLIENT.call("#{ip}:443", decoy)) do
    its('stdout') { should match(/subject=.*(microsoft|#{Regexp.escape(decoy.split('.').last(2).join('.'))})/i) }
    its('stdout') { should match(/Verify return code: 0 \(ok\)/) }
    its('stdout') { should_not match(/self.signed/i) }
  end
end

control 'disfarce-02' do
  impact 1.0
  title 'Sondado com um SNI qualquer, o servidor nao se denuncia'
  desc <<~DESC
    Segunda sonda comum: mandar um SNI aleatorio e ver se a resposta muda. Um
    proxy mal disfarcado responde de um jeito diferente — erro proprio,
    certificado autoassinado, conexao derrubada de um jeito caracteristico —
    e essa diferenca e a assinatura que o bloqueio usa.
  DESC

  describe command(S_CLIENT.call("#{ip}:443", 'exemplo-que-nao-existe.invalid')) do
    its('stdout') { should_not match(/proxy-do-rafa|sing-box|self.signed certificate/i) }
  end
end

control 'disfarce-03' do
  impact 1.0
  title 'A porta de origem do WebSocket nao responde a quem nao e a Cloudflare'
  desc <<~DESC
    O caminho WebSocket vive em 127.0.0.1:8443, atras do demultiplexador. Nao ha
    regra nenhuma para essa porta no security group.

    Se ela responder daqui, alguem a exps de novo — e o WebSocket passa a ser
    alcancavel sem passar pelo demultiplexador, com o certificado autoassinado
    da origem visivel para quem sondar.

    Falha esperada: timeout ou conexao recusada.
  DESC

  describe command("echo | timeout 8 openssl s_client -connect #{ip}:#{porta_websocket} -servername #{dominio} 2>&1") do
    its('exit_status') { should_not eq 0 }
  end
end

control 'disfarce-04' do
  impact 0.7
  title 'O caminho de reserva responde pela Cloudflare'
  desc <<~DESC
    Confere que o registro DNS existe, esta no modo proxied e que a borda da
    Cloudflare termina TLS pelo nosso dominio. Nao testa o tunel em si — testa
    que o caminho ate ele esta de pe.
  DESC

  describe command(S_CLIENT.call("#{dominio}:443", dominio)) do
    its('stdout') { should match(/Verify return code: 0 \(ok\)/) }
  end

  # O recurso `host` foi removido daqui: ele nao roda no transporte local do
  # container e ficava eternamente SKIPPED — e controle pulado faz o InSpec sair
  # com 101, que derrubava o resto do fluxo. Alem disso era redundante: o
  # s_client acima ja prova que a borda da Cloudflare aceita conexao e termina
  # TLS pelo nosso dominio, que e mais forte do que "a porta responde".
end

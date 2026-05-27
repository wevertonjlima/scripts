Guia Definitivo: Sincronização de Tempo (NTP) em Ambientes Air-Gapped (Windows + Linux)


Em ambientes isolados, o erro **"Username or Password Incorrect"** ao integrar um Linux no AD quase nunca é culpa da senha. O vilão é o Kerberos Pre-authentication, que exige que o relógio do cliente e do DC estejam em sintonia.

### Cenário de Referência:

- **Domínio:** `contoso.corp`
    
- **Domain Controller (PDC):** `alfa` (192.168.15.25)
    
- **Cliente Linux:** `bishop` (192.168.15.50)
    

---

## 1. O Sintoma do Problema (O Erro de Senha)

Ao tentar o join no `bishop` sem o tempo estar sincronizado, você verá algo assim:

Bash

```
[localroot@bishop ~]$ realm join --user=usr_joinad contoso.corp
Password for usr_joinad: 
realm: Quiting: Kerberos authentication failed: Password incorrect
```

_Mesmo com a senha correta, o DC recusa a conexão porque o "timestamp" do pacote enviado pelo Linux está fora da janela de 5 minutos do Active Directory._

---

## 2. Configurando a "Fonte da Verdade" (Windows Server)

No DC `alfa`, como não há internet, precisamos dizer ao Windows que ele deve ser a autoridade máxima de tempo para a rede interna.

**No PowerShell (Executado no DC ALFA):**

PowerShell

```
# 1. Abre a porta de tempo no Firewall
New-NetFirewallRule -DisplayName "NTP Server (UDP-In)" -Direction Inbound -LocalPort 123 -Protocol UDP -Action Allow

# 2. Configura o anúncio como fonte confiável (AnnounceFlags 5 = Master)
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\W32Time\Config" /v AnnounceFlags /t REG_DWORD /d 5 /f

# 3. Define o relógio local como estável e reinicia
w32tm /config /localclockdispersion:0 /reliable:YES /update
Restart-Service w32time
```

---

## 3. O Ajuste no Cliente (Linux Bishop)

No Linux, o serviço **Chrony** deve ser configurado para ignorar a internet e "olhar" apenas para o IP do DC `alfa`.

**Arquivo `/etc/chrony.conf` no servidor Bishop:**

Plaintext

```
# server 0.pool.ntp.org iburst (COMENTADO)
server 192.168.15.25 iburst prefer trust
```

**Comandos de Sincronização:**

Bash

```
[localroot@bishop ~]$ sudo systemctl restart chronyd
[localroot@bishop ~]$ sudo chronyc makestep
200 OK
```

---

## 4. Validando a Sincronia (A Prova Real)

Agora, o comando `tracking` deve mostrar que o Linux "casou" com o DC. Esta é a tela que o seu leitor deve ver para saber que o join vai funcionar:

Bash

```
[localroot@bishop ~]$ chronyc tracking
Reference ID    : C0A80F19 (192.168.15.25)
Stratum         : 2
Ref time (UTC)  : Wed May 06 18:25:12 2026
System time     : 0.000000002 seconds slow of NTP time
Leap status     : Normal
```

E no `timedatectl`, o status final de sucesso:

Bash

```
[localroot@bishop ~]$ timedatectl
System clock synchronized: yes
NTP service: active
```

---

### 5. A Prova Final: Validando com `chronyc sources -v`

Para garantir que o `bishop` não está apenas tentando falar com o `alfa`, mas que ele **aceitou** o DC como sua fonte de tempo, utilizamos o comando de fontes.

No cenário **Contoso.corp**, este é o feedback esperado:

Bash

```
[localroot@bishop ~]$ chronyc sources -v

  .-- Source mode  '^' = server, '=' = peer, '#' = local clock.
 / .- Source state '*' = current best, '+' = combined, '-' = not combined,
| /             'x' = may be in error, '~' = too variable, '?' = unusable.
||                                                 .- xxxx [ yyyy ] +/- zzzz
||      Reachability register (octal) -.           |  xxxx = adjusted offset,
||      Log2(Polling interval) --.      |          |  yyyy = measured offset,
||                                \     |          |  zzzz = estimated error.
||                                 |    |           \
MS Name/IP address         Stratum Poll Reach LastRx Last sample               
===============================================================================
^* alfa.contoso.corp             1   6    377    15    -12us[  -15us] +/-  450us
^? time100.stupi.se              0   6     0     -     +0ns[   +0ns] +/-    0ns
^? a.ntp.netplanety.com.br       0   6     0     -     +0ns[   +0ns] +/-    0ns
^? b.ntp.netplanety.com.br       0   6     0     -     +0ns[   +0ns] +/-    0ns
^? time.cloudflare.com           0   6     0     -     +0ns[   +0ns] +/-    0ns
```

#### Como interpretar os dados factuais desta tela:

- **Símbolo `^*`**: O momento "Eureca". O `^` indica um servidor e o `*` confirma que este é o **current best** (fonte sincronizada). Se aparecer `^?`, a fonte é inutilizável (geralmente por erro de firewall ou o DC não estar como `reliable`).
    
- **Stratum 1 ou 2**: Indica que o `alfa` é a autoridade de tempo na rede.
    
- **Reach 377**: Este número em octal significa que as últimas 8 tentativas de contato foram 100% bem-sucedidas. Se o número for baixo (como 1, 3 ou 17), a conexão está instável.
    
- **LastRx**: Indica há quantos segundos o Linux recebeu o último pacote de tempo do DC.
    

### Por que isso confirma o sucesso do Join?

O Active Directory utiliza o **Kerberos**. Quando o `chronyc sources` exibe o asterisco, ele confirma que o desvio de tempo (**Offset**) é mínimo (no exemplo, apenas `-12us`, ou microssegundos). Com essa precisão, o ticket de autenticação enviado pelo Linux será aceito pelo DC `alfa` sem questionamentos de segurança, eliminando o erro de "Password Incorrect".

---

**Dica do Billy:** Se você rodar o comando e o nome do DC não aparecer, tente usar o IP diretamente no `/etc/chrony.conf`. Às vezes, em ambientes isolados, o DNS demora mais para subir do que o serviço de tempo, e o Chrony pode "desistir" de resolver o nome no boot.

## 6. O Resultado Final

Com o `Leap status: Normal`, o Kerberos agora aceita a credencial. O comando de join finalmente retorna o sucesso:

Bash

```
[localroot@bishop ~]$ realm join --user=usr_joinad contoso.corp
Password for usr_joinad: 
[localroot@bishop ~]$ # Sucesso! Sem mensagens de erro.
```

---

### Resumo :

1. **Windows:** Use `AnnounceFlags 5` e `reliable:YES`.
    
2. **Linux:** Aponte o `chrony` para o IP do DC com as flags `prefer trust`.
    
3. **Validação:** O `Reference ID` no Linux deve ser obrigatoriamente o IP do seu DC.
    

---

**Pro-Tip:** Tenha atenção com o serviço **`w32tm`** no Windows, pois ele é sensível. Se após o comando o serviço não subir, verifique se não há outro servidor de tempo (como um roteador) competindo na mesma rede!

# predator-kb

Controle do teclado RGB de 4 zonas dos notebooks **Acer Predator** no Linux,
com integração opcional ao [Omarchy](https://omarchy.org/).

Testado no **Predator PH315-54** (Helios 300) com kernel 7.2, Hyprland e Omarchy.

```bash
predator-kb color ff0055                        # todas as zonas
predator-kb color ff0000 ffaa00 00ff88 0088ff   # uma cor por zona
predator-kb wave -s 6                           # onda arco-íris
predator-kb breath 8000ff -s 3 -b 60            # respiração roxa
predator-kb off
```

## Por que isso é necessário

O `acer-wmi` que vem no kernel **não expõe o RGB** desse teclado — não há nada em
`/sys/class/leds`. Os métodos existem no firmware, na interface WMI de gaming da
Acer (GUID `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56`), mas só o driver
[`facer`](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module)
os implementa.

Este projeto **não reimplementa o driver**. Ele instala o `facer` via DKMS e
entrega em cima dele o que faltava para o uso no dia a dia: uma CLI, persistência
do perfil entre reboots e suspensões, e a integração com o Omarchy.

O `facer` cria dois char devices, já com permissão `0666` — nada aqui precisa de
sudo depois da instalação:

| Device | Payload | Uso |
|---|---|---|
| `/dev/acer-gkbbl-static-0` | 4 bytes: `zona_bitmask, R, G, B` | cor fixa por zona |
| `/dev/acer-gkbbl-0` | 16 bytes: `modo, vel, brilho, flag, dir, R, G, B, 0, 1, …` | efeitos e brilho |

## Instalação

Requisitos: `dkms`, `git`, `make`, `gcc` e os **headers do seu kernel**
(`linux-headers`, `linux-lts-headers`, `linux-omarchy-headers`, … conforme o kernel).

```bash
git clone https://github.com/luccas-santos01/predator-kb.git
cd predator-kb
./install.sh
```

Rode como seu usuário normal — o script pede `sudo` só nas partes privilegiadas,
e precisa de um terminal de verdade para a senha. Use `--no-omarchy` para pular
o menu e os atalhos.

O instalador verifica o modelo e a presença da WMI de gaming antes de começar,
compila o `facer` via DKMS (que o recompila sozinho a cada novo kernel) e faz
blacklist do `acer_wmi` — os dois registram os mesmos GUIDs e não convivem.

> O `facer` é um **fork do `acer-wmi`**, então isso é uma troca de driver, não uma
> adição. Você não perde funcionalidade; ganha o RGB, o turbo e o controle de fan.

Para remover tudo e devolver o `acer_wmi`: `./uninstall.sh`

## Uso

```
CORES ESTÁTICAS
  predator-kb color <cor>                    todas as 4 zonas na mesma cor
  predator-kb color <c1> <c2> <c3> <c4>      uma cor por zona (esq → dir)
  predator-kb zone <1-4> <cor>               muda só uma zona

EFEITOS
  predator-kb breath <cor>                   respiração
  predator-kb neon                           neon
  predator-kb wave                           onda de arco-íris
  predator-kb shift <cor>                    deslizante
  predator-kb zoom <cor>                     zoom

OPÇÕES    -s <0-9> velocidade   -b <0-100> brilho   -d <1|2> direção

BRILHO    predator-kb brightness <0-100> | up | down | off | on | toggle
PERFIS    predator-kb save <nome> | load <nome> | list
ESTADO    predator-kb status | restore
```

Cores aceitam `RRGGBB`, `#RRGGBB` ou nomes (`red`, `azul`, `roxo`, `laranja`, …).

## Persistência

O firmware reseta o backlight ao reiniciar e ao acordar da suspensão. O instalador
cobre os dois casos:

- `~/.config/systemd/user/predator-kb-restore.service` — reaplica no login
- `/usr/lib/systemd/system-sleep/predator-kb` — reaplica ao acordar

Ambos rodam `predator-kb restore`, que lê `~/.config/predator-kb/profile` —
atualizado a cada comando. Ou seja: o último visual que você usou é o que volta.

## Integração com o Omarchy

Instalada automaticamente quando `~/.config/omarchy` existe.

- **`SUPER + SHIFT + K`** abre "Teclado RGB" no omarchy-menu, com submenus de cor
  (incluindo cor personalizada por prompt e um degradê por zona), efeito, brilho
  e perfis
- **`XF86KbdBrightnessUp/Down`** ajustam o brilho em ±20, se o Fn do seu teclado
  emitir essas teclas

A entrada do menu tem `when: test -w /dev/acer-gkbbl-0`, então some sozinha se o
driver não estiver carregado.

Os blocos inseridos em `bindings.lua` e `omarchy-menu.jsonc` ficam entre
marcadores `predator-kb:begin`/`:end`, então reinstalar não duplica e desinstalar
remove sem deixar resto. Os dois arquivos são copiados para `.bak.<timestamp>`
antes de qualquer alteração.

## Outros modelos

O `facer` lista suporte a boa parte da linha Predator/Nitro
(PH315-52/53/54/55, PH317-53/54, PT315-51, PHN18-71, AN515-58 e outros) —
veja a [tabela do upstream](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module#supported-models).
Se o seu modelo tem 4 zonas e está nessa lista, isto aqui deve funcionar.

Não há suporte a teclado *per-key* — a limitação é do firmware/WMI, não do driver.

O instalador avisa mas não impede a instalação em modelos fora da lista. Se os
devices aparecerem e o teclado não responder, seu modelo provavelmente precisa de
um quirk novo no `facer` — o issue vai para o [upstream](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module/issues).

## Diagnóstico

```bash
dkms status | grep facer      # deve dizer "installed"
lsmod | grep facer            # deve estar carregado
ls -l /dev/acer-gkbbl-*       # devem existir, com permissão crw-rw-rw-
sudo dmesg | grep -i facer
predator-kb status
```

Se o RGB parar depois de uma atualização de kernel, quase sempre é o DKMS que não
recompilou por falta dos headers na versão nova. Instale os headers e rode
`sudo dkms autoinstall`.

## Créditos

O driver é o [`facer`](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module),
de Jafar Akhondali e contribuidores, licenciado sob GPL-2.0 — é ele que faz o
trabalho de verdade. Este repositório não redistribui o código dele; o
`install.sh` clona o upstream na hora da instalação.

Os scripts deste projeto estão sob licença MIT (veja `LICENSE`).

#!/bin/sh
# Gera "Claude Remote Manager.exe" a partir de app/Lancador.cs com o compilador C# do Mono (Linux).
# Uso: ferramentas/Gerar-Exe.sh [saida.exe]   (precisa: apt-get install mono-mcs libmono-system-windows-forms4.0-cil)
set -e
cd "$(dirname "$0")/.."
saida="${1:-Claude Remote Manager.exe}"
mcs -nologo -sdk:4.5 -target:winexe -optimize+ -platform:anycpu -win32icon:app/icone.ico -r:System.Windows.Forms.dll -out:"$saida" app/Lancador.cs
echo "Gerado: $saida"

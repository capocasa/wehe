# Package
version     = "0.1.0"
author      = "Carlo"
description = "Hawaiian word decomposition — uncover the hidden"
license     = "MIT"
srcDir      = "src"
bin         = @["wehe"]

# Dependencies
requires "nim >= 2.0.0"
requires "mummy"

task importAndrews, "Download and import Andrews 1865 dictionary":
  exec "nim c -d:ssl --path:src -r tools/import_andrews.nim"

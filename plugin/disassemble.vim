if exists("g:loaded_disassemble")
  finish
endif
let g:loaded_disassemble = 1

command! Disassemble call disassemble#Disassemble()
command! DisassembleFocus call disassemble#Focus()
command! DisassembleConfig call disassemble#Config()


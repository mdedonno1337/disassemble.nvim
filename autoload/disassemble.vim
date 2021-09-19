let b:disassemble_popup_window_id = v:false
let b:compilation_command = "make " . expand("%:r") . "_debug"
let b:compilation_command_default = "gcc " . expand("%") . " -o " . expand("%:r") . " -g"
let b:objdump_command = "objdump -C -l -S --no-show-raw-insn -d " . expand("%:r")
let b:do_compile = v:true

function! disassemble#ConfigureCompilation() abort range
  let b:compilation_command = input("Compilation command> ", b:compilation_command)
endfunction

function! disassemble#Disassemble(cmdmods, arg)
  if b:disassemble_popup_window_id
    call disassemble#Close()
  endif

  if !filereadable(expand("%:r"))
    if !b:do_compile
      echohl WarningMsg
      echomsg "the file '" . expand("%:r") . "' is not readable"
      echohl None
      return 1
    else
      " TODO: Check if the complation is OK
      " TODO: Refactoring into a 'compile' function, and merge with the second call
      call system(b:compilation_command)
      if v:shell_error
        call system(b:compilation_command_default)
        if v:shell_error
          echohl WarningMsg
          echomsg "Error while compiling. Check the compilation command."
          echohl None
          return 1
        endif
      endif
    endif
  endif

  let b:has_debug_info = system("file " . expand("%:r"))
  if match(b:has_debug_info, "with debug_info") == -1
    echohl WarningMsg
    echomsg "the file '" . expand("%:r") . "' does not have debug information"
    echohl None
    return 1
  endif

  " Extract the asm code
  " TODO: Refactoring
  let b:asm_tmp_file = tempname()
  let b:error_tmp_file = tempname()

  let local_objdump_command = b:objdump_command . " 1>" . b:asm_tmp_file . " 2>" . b:error_tmp_file
  call system(local_objdump_command)

  " Check if the C source code is more recent than the object file
  " Recompiles the code as needed
  let b:compilation_error = readfile(b:error_tmp_file)
  let b:compilation_error = string(b:compilation_error)

  if match(b:compilation_error, "is more recent than object file") != -1
    call system(b:compilation_command)
    call system(local_objdump_command)
  endif
  let b:lines = systemlist("expand -t 4 " . b:asm_tmp_file)

  " Search the current line
  let current_line_checked = line(".")
  let pos_current_line_in_asm = ['', -1]
  let lines_searched = 0

  while pos_current_line_in_asm[1] < 0
    let pos_current_line_in_asm = matchstrpos(b:lines, expand("%:p") . ":" . current_line_checked . "$")
    let current_line_checked += 1

    let lines_searched += 1
    if lines_searched >= 20
      echohl WarningMsg
      echomsg "this is line not found in the asm file ... ? contact the maintainer with an example of this situation"
      echohl None
      return 1
    endif
  endwhile
  let pos_next_line_in_asm = matchstrpos(b:lines, expand("%:p") . ":", pos_current_line_in_asm[1] + 1)
  let b:pos = [1, 0]

  " Only select the current chunk of asm
  let b:lines = b:lines[pos_current_line_in_asm[1]:pos_next_line_in_asm[1] - 1]

  " Set the popup options
  let width = max(map(copy(b:lines), 'strlen(v:val)'))
  let height = pos_next_line_in_asm[1] - pos_current_line_in_asm[1]

  " Create the popup window
  let buf = nvim_create_buf(v:false, v:true)
  let opts = {"relative": "cursor",
        \ "width": width,
        \ "height": height,
        \ "col": 0,
        \ "row": 1,
        \ "anchor": "NW",
        \ "style": "minimal",
        \ "focusable": v:true,
        \ }

  let b:disassemble_popup_window_id = nvim_open_win(buf, 0, opts)

  call nvim_buf_set_lines(buf, 0, height, v:false, b:lines)
  call nvim_buf_set_option(buf, "filetype", "asm")
  call nvim_win_set_cursor(b:disassemble_popup_window_id, b:pos)
endfunction

function! disassemble#Close() abort
  if get(b:, "disassemble_popup_window_id", v:false)
    silent! call nvim_win_close(b:disassemble_popup_window_id, v:true)
    let b:disassemble_popup_window_id = v:false
  endif
endfunction

function! disassemble#Focus() abort
  call nvim_set_current_win(b:disassemble_popup_window_id)
endfunction

augroup disassembleOnCursorMoveGroup
  autocmd!
  autocmd CursorMoved *.c call disassemble#Close()
augroup END


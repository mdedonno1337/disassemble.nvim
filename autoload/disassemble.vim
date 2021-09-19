function! s:getConfig() abort
  " Create the variable to store the window id
  if !exists("b:disassemble_popup_window_id")
    let b:disassemble_popup_window_id = v:false
  endif
  
  " Check if the plugin should compile automatically
  if !exists("b:do_compile")
    let b:do_compile = v:true
  endif
  
  " Check if the plugin is already configured
  if ! exists("b:disassemble_config")
    call s:setConfiguration()
  end
endfunction

function! disassemble#Config() abort range
    call s:setConfiguration()
endfunction

function! s:setConfiguration() abort
  " Create the variables to store the temp files
  if !exists("b:asm_tmp_file")
    let b:asm_tmp_file = tempname()
  endif
  
  if !exists("b:error_tmp_file")
    let b:error_tmp_file = tempname()
  endif
  " Set the default values for the compilation and objdump commands
  if !exists("b:disassemble_config")
    let b:disassemble_config = {
      \ "compilation": "gcc " . expand("%") . " -o " . expand("%:r") . " -g",
      \ "objdump": "objdump -C -l -S --no-show-raw-insn -d " . expand("%:r")
      \ }
  end
  
  " Ask the user for the compilation and objdump extraction commands
  let b:disassemble_config["compilation"] = input("compilation command> ", b:disassemble_config["compilation"])
  let b:disassemble_config["objdump"] = input("objdump command> ", b:disassemble_config["objdump"])
  let b:disassemble_config["objdump_with_redirect"] = b:disassemble_config["objdump"] . " 1>" . b:asm_tmp_file . " 2>" . b:error_tmp_file
  
  redraw

  return
endfunction

function! disassemble#Disassemble()
  call s:getConfig()
  
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
      " TODO: Refactoring into a 'compile' function, and merge with the second call
      let compilation_result = system(b:disassemble_config["compilation"])
      if v:shell_error
        echohl WarningMsg
        echomsg "Error while compiling. Check the compilation command."
        echo "\n"

        echohl Question
        echomsg "> " . b:disassemble_config["compilation"]
        echo "\n"

        echohl ErrorMsg
        echo compilation_result
        echo "\n"

        echohl None

        return 1
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
  call system(b:disassemble_config["objdump_with_redirect"])

  " Check if the C source code is more recent than the object file
  " Recompiles the code as needed
  let b:compilation_error = readfile(b:error_tmp_file)
  let b:compilation_error = string(b:compilation_error)

  if match(b:compilation_error, "is more recent than object file") != -1
    call system(b:disassemble_config["compilation"])
    call system(b:disassemble_config["objdump_with_redirect"])
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
  if get(b:,"auto_close", v:true)
    if get(b:, "disassemble_popup_window_id", v:false)
      silent! call nvim_win_close(b:disassemble_popup_window_id, v:true)
      let b:disassemble_popup_window_id = v:false
    endif
  else
    let b:auto_close = v:true
  endif
endfunction

function! disassemble#Focus() abort
  let b:auto_close = v:false
  call nvim_set_current_win(b:disassemble_popup_window_id)
endfunction

augroup disassembleOnCursorMoveGroup
  autocmd!
  autocmd CursorMoved,BufLeave *.c call disassemble#Close()
augroup END


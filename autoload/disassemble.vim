"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Configuration
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

if !exists("g:disassemble_focus_on_second_call")
  let g:disassemble_focus_on_second_call = v:false
end

if !exists("g:disassemble_do_compile")
  let g:disassemble_do_compile = v:true
end

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Configuration functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:getConfig() abort
  " Create the variable to store the window id
  if !exists("b:disassemble_popup_window_id")
    let b:disassemble_popup_window_id = v:false
  endif
  
  " Check if the plugin should compile automatically
  if !exists("b:do_compile")
    let b:do_compile = g:disassemble_do_compile
  endif
  
  " Check if the plugin is already configured
  if !exists("b:disassemble_config")
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
          \ "objdump": "objdump -C -l -f -S --no-show-raw-insn -d " . expand("%:r")
          \ }
  end
  
  " Try to search a compilation command in the first 10 lines of the file
  let [matched_line, matched_start] = matchstrpos(getline(1, 10), "gcc ")[1:2]
  if matched_line != -1
    let b:disassemble_config["compilation"] = getline(matched_line + 1)[matched_start:]
  endif
  
  " Ask the user for the compilation and objdump extraction commands
  if get(b:, "do_compile")
    let b:disassemble_config["compilation"] = input("compilation command> ", b:disassemble_config["compilation"])
  endif
  
  let b:disassemble_config["objdump"] = input("objdump command> ", b:disassemble_config["objdump"])
  let b:disassemble_config["objdump_with_redirect"] = b:disassemble_config["objdump"]
        \ . " 1>" . b:asm_tmp_file
        \ . " 2>" . b:error_tmp_file
  
  redraw
  echomsg "Disassemble.nvim configured for this buffer!"

  return
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Compilation function
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:do_compile() abort range
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
    
  else
    return 0
    
  endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Objectdump extraction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:do_objdump() abort
  " Reset the output variables
  let b:compilation_error = v:false
  let b:lines = v:false
  
  " Extract the objdump information to the `error_tmp_file` and `asm_tmp_file` files
  call system(b:disassemble_config["objdump_with_redirect"])
  if v:shell_error
    return 1
  endif
  
  " Get the error from the temporary file
  let b:compilation_error = readfile(b:error_tmp_file)
  let b:compilation_error = string(b:compilation_error)
  
  " Return the error code 128 if the C file is more recent that the ELF file
  if match(b:compilation_error, "is more recent than object file") != -1
    return 128
  endif
  
  " Get the content of the objdump file
  let b:lines = systemlist("expand -t 4 " . b:asm_tmp_file)
  if v:shell_error
    return 1
  endif
  
  " Return OK
  return 0
endfunction

function! s:get_objdump() abort
  " Check the presence of the ELF file
  if !filereadable(expand("%:r"))
    if !b:do_compile
      echohl WarningMsg
      echomsg "the file '" . expand("%:r") . "' is not readable"
      echohl None
      return 1
    else
      if s:do_compile()
        return 1
      endif
    endif
  endif
  
  " Check if the binary file has debug informations
  let b:has_debug_info = system("file " . expand("%:r"))
  if match(b:has_debug_info, "with debug_info") == -1
    echohl WarningMsg
    echomsg "the file '" . expand("%:r") . "' does not have debug information"
    echohl None
    return 1
  endif
  
  " Get the objdump content
  let objdump_return_code = s:do_objdump()
  
  " Unknown error in the function
  if objdump_return_code == 1
    return 1
    
  " Check if the C source code is more recent than the object file
  " Try to recompile and redump the objdump content
  elseif objdump_return_code == 128
    if s:do_compile()
      return 1
    endif
    return s:get_objdump()
    
  else
    return 0
    
  endif
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Data processing
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:searchCurrentLine() abort range
  " Search the current line
  let current_line_checked = line(".")
  let pos_current_line_in_asm = ["", -1]
  let lines_searched = 0

  while pos_current_line_in_asm[1] < 0
    let pos_current_line_in_asm = matchstrpos(b:lines, expand("%:p") . ":" . current_line_checked . "$")
    if pos_current_line_in_asm[1] == -1
      " Add support for (discriminator) lines; multi-path to get to an asm line
      let pos_current_line_in_asm = matchstrpos(b:lines, expand("%:p") . ":" . current_line_checked . " ")
    endif
    
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
  
  return [pos_current_line_in_asm[1], pos_next_line_in_asm[1]]
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Main functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! disassemble#Disassemble()
  " Load the configuration for this buffer
  call s:getConfig()
  
  " Remove or focus the popup
  if b:disassemble_popup_window_id
    if g:disassemble_focus_on_second_call
      call disassemble#Focus()
      return 0
    else
      call disassemble#Close()
    endif
  endif

  " Extract the objdump content to the correct buffer variables
  if s:get_objdump()
    return 1
  endif

  let [pos_current_line_in_asm, pos_next_line_in_asm] = s:searchCurrentLine()
  let b:pos = [1, 0]

  " Only select the current chunk of asm
  let b:lines = b:lines[pos_current_line_in_asm:pos_next_line_in_asm - 1]

  " Set the popup options
  let width = max(map(copy(b:lines), "strlen(v:val)"))
  let height = pos_next_line_in_asm - pos_current_line_in_asm

  " Create the popup window
  let buf = nvim_create_buf(v:false, v:true)
  let opts = { "relative": "cursor",
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

function! disassemble#DisassembleFull() abort
  " Load the configuration for this buffer
  call s:getConfig()

  " Extract the objdump content to the correct buffer variables
  if s:get_objdump()
    return 1
  endif

  let [pos_current_line_in_asm, pos_next_line_in_asm] = s:searchCurrentLine()
  
  " Create the new buffer
  let bufid = nvim_create_buf(v:true, v:true)
  call nvim_buf_set_name(bufid, "[Disassembled] " . expand("%:r"))
  call nvim_buf_set_lines(bufid, 0, 0, v:false, b:lines)
  call nvim_buf_set_option(bufid, "filetype", "asm")
  call nvim_buf_set_option(bufid, "readonly", v:true)

  " Focus the buffer
  execute 'buffer ' . bufid
  
  " Open the current line
  call nvim_win_set_cursor(0, [pos_current_line_in_asm+2, 0])

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

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Autocommands
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

augroup disassembleOnCursorMoveGroup
  autocmd!
  autocmd CursorMoved,BufLeave *.c call disassemble#Close()
augroup END


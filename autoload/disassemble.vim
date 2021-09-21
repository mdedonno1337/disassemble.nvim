"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Configuration
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let g:disassemble_focus_on_second_call = get(g:, "disassemble_focus_on_second_call", v:false)
let g:disassemble_enable_compilation = get(g:, "disassemble_enable_compilation", v:true)

let s:objdump_default_command = "objdump --demangle --line-numbers --file-headers --file-offsets --source --no-show-raw-insn --disassemble " . expand("%:r")
let s:gcc_default_command = "gcc " . expand("%") . " -o " . expand("%:r") . " -g"

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Configuration functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:getConfig() abort
  " Create the variable to store the window id
  let b:disassemble_popup_window_id = get(b:, "disassemble_popup_window_id", v:false)

  " Check if the plugin should compile automatically
  let b:enable_compilation = get(b:, "enable_compilation", g:disassemble_enable_compilation)

  " Check if the plugin is already configured
  if !exists("b:disassemble_config")
    call s:setConfiguration()
  endif
endfunction

function! disassemble#Config() abort
  call s:setConfiguration()
endfunction

function! s:setConfiguration() abort
  " Create the variables to store the temp files
  let b:asm_tmp_file = get(b:, "asm_tmp_file", tempname())
  let b:error_tmp_file = get(b:, "error_tmp_file", tempname())

  " Set the default values for the compilation and objdump commands
  let b:disassemble_config = get( b:, "disassemble_config", {
        \ "compilation": s:gcc_default_command,
        \ "objdump": s:objdump_default_command
        \ } )

  " Try to search a compilation command in the first 10 lines of the file
  let [matched_line, matched_start, matched_ends] = matchstrpos(getline(1, 10), "compile: ")[1:3]
  if matched_line != -1
    let b:disassemble_config["compilation"] = getline(matched_line + 1)[matched_ends:]
  endif

  " Ask the user for the compilation and objdump extraction commands
  if b:enable_compilation
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

function! s:do_compile() abort
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
  let b:objdump_asm_output = v:false

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
  let b:objdump_asm_output = systemlist("expand -t 4 " . b:asm_tmp_file)
  if v:shell_error
    return 1
  endif

  " Return OK
  return 0
endfunction

function! s:get_objdump() abort
  " Check the presence of the ELF file
  if !filereadable(expand("%:r"))
    if !b:enable_compilation
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

  if objdump_return_code == 1
    " Unknown error in the function
    return 1

  elseif objdump_return_code == 128
    " Check if the C source code is more recent than the object file
    " Try to recompile and redump the objdump content
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

function! s:searchCurrentLine() abort
  " Search the current line
  let current_line_checked = line(".")
  let pos_current_line_in_asm = ["", -1]
  let lines_searched = 0

  while pos_current_line_in_asm[1] < 0
    let pos_current_line_in_asm = matchstrpos(b:objdump_asm_output, expand("%:p") . ":" . current_line_checked . '\(\s*(discriminator \d*)\)*$')

    let current_line_checked += 1

    let lines_searched += 1
    if lines_searched >= 20
      echohl WarningMsg
      echomsg "this is line not found in the asm file ... ? contact the maintainer with an example of this situation"
      echohl None
      return 1
    endif
  endwhile

  " Search the next occurence of the filename
  let pos_next_line_in_asm = matchstrpos(b:objdump_asm_output, expand("%:p") . ":", pos_current_line_in_asm[1] + 1)

  " If not found, it's probably because this code block is at the end of a
  " section. This will search the start of the next section.
  if pos_next_line_in_asm[1] == -1
    let pos_next_line_in_asm = matchstrpos(b:objdump_asm_output, '\v^\x+\s*', pos_current_line_in_asm[1] + 1)
  endif

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

  " Only select the current chunk of asm
  let b:objdump_asm_output = b:objdump_asm_output[pos_current_line_in_asm:pos_next_line_in_asm - 1]

  " Set the popup options
  let width = max(map(copy(b:objdump_asm_output), "strlen(v:val)"))
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

  call nvim_buf_set_lines(buf, 0, height, v:false, b:objdump_asm_output)
  call nvim_buf_set_option(buf, "filetype", "asm")
  call nvim_win_set_cursor(b:disassemble_popup_window_id, [1, 0])

  augroup disassembleOnCursorMoveGroup
    autocmd!
    autocmd CursorMoved,BufLeave *.c,*.cpp call disassemble#Close()
  augroup END
endfunction

function! disassemble#DisassembleFull() abort
  " Load the configuration for this buffer
  call s:getConfig()

  " Extract the objdump content to the correct buffer variables
  if s:get_objdump()
    return 1
  endif

  let [pos_current_line_in_asm, pos_next_line_in_asm] = s:searchCurrentLine()

  " Create or reuse the last buffer
  if !get(b:, "buffer_full_asm", v:false)
    let b:buffer_full_asm = nvim_create_buf(v:true, v:true)
    call nvim_buf_set_name(b:buffer_full_asm, "[Disassembled] " . expand("%:r"))
  else
    call nvim_buf_set_option(b:buffer_full_asm, "readonly", v:false)
  endif

  " Set the content to the buffer
  call nvim_buf_set_lines(b:buffer_full_asm, 0, 0, v:false, b:objdump_asm_output)

  " Set option for that buffer
  call nvim_buf_set_option(b:buffer_full_asm, "filetype", "asm")
  call nvim_buf_set_option(b:buffer_full_asm, "readonly", v:true)

  " Focus the buffer
  execute 'buffer ' . b:buffer_full_asm

  " Open the current line
  call nvim_win_set_cursor(0, [pos_current_line_in_asm+2, 0])

endfunction

function! disassemble#Close() abort
  if get(b:,"auto_close", v:true)
    if get(b:, "disassemble_popup_window_id", v:false)
      silent! call nvim_win_close(b:disassemble_popup_window_id, v:true)
      let b:disassemble_popup_window_id = v:false

      " Remove the autocmd for the files for performances reasons
      augroup disassembleOnCursorMoveGroup
        autocmd!
      augroup END
    endif
  else
    let b:auto_close = v:true
  endif
endfunction

function! disassemble#Focus() abort
  let b:auto_close = v:false
  if get(b:, "disassemble_popup_window_id", v:false)
    silent! call nvim_set_current_win(b:disassemble_popup_window_id)
  else
    echohl WarningMsg
    echomsg "No popup at the moment"
    echohl None
  endif
endfunction


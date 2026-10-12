" Refresh only the suggestion buffer; never move focus or reload the draft.
wincmd l
setlocal buftype=nofile bufhidden=wipe readonly nomodifiable noswapfile
let s:suggestion_buffer = bufnr('%')
let s:suggestion_path = expand('%:p')
let s:ready_path = expand('%:p:h') . '/ready'
function! s:RefreshSuggestion(timer) abort
    if !bufloaded(s:suggestion_buffer)
        call timer_stop(a:timer)
        return
    endif
    if !filereadable(s:ready_path)
        return
    endif
    let lines = readfile(s:suggestion_path)
    call setbufvar(s:suggestion_buffer, '&readonly', 0)
    call setbufvar(s:suggestion_buffer, '&modifiable', 1)
    call deletebufline(s:suggestion_buffer, 1, '$')
    call setbufline(s:suggestion_buffer, 1, lines)
    call setbufvar(s:suggestion_buffer, '&modified', 0)
    call setbufvar(s:suggestion_buffer, '&modifiable', 0)
    call setbufvar(s:suggestion_buffer, '&readonly', 1)
    call timer_stop(a:timer)
    redraw
endfunction
call timer_start(100, function('s:RefreshSuggestion'), {'repeat': -1})
wincmd h

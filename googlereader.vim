"=============================================================================
" File: googlereader.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 30-Jun-2010.
" Version: 2.2
" WebPage: http://github.com/mattn/googlereader-vim/tree/master
" Usage:
"
"   :GoogleReader
"
" GetLatestVimScripts: 2678 1 :AutoInstall: googlereader.vim
" Script type: plugin

let g:googlereader_vim_version = "2.2"
if &compatible
  finish
endif

if !executable('curl')
  echoerr "GoogleReader: require 'curl' command"
  finish
endif

let s:LIST_BUFNAME = '==GoogleReader Entries=='
let s:CONTENT_BUFNAME = '==GoogleReader Content=='

function! s:wcwidth(ucs)
  let ucs = a:ucs
  if (ucs >= 0x1100
   \  && (ucs <= 0x115f
   \  || ucs == 0x2329
   \  || ucs == 0x232a
   \  || (ucs >= 0x2e80 && ucs <= 0xa4cf
   \      && ucs != 0x303f)
   \  || (ucs >= 0xac00 && ucs <= 0xd7a3)
   \  || (ucs >= 0xf900 && ucs <= 0xfaff)
   \  || (ucs >= 0xfe30 && ucs <= 0xfe6f)
   \  || (ucs >= 0xff00 && ucs <= 0xff60)
   \  || (ucs >= 0xffe0 && ucs <= 0xffe6)
   \  || (ucs >= 0x20000 && ucs <= 0x2fffd)
   \  || (ucs >= 0x30000 && ucs <= 0x3fffd)
   \  ))
    return 2
  endif
  return 1
endfunction

function! s:wcswidth(str)
  let mx_first = '^\(.\)'
  let str = a:str
  let width = 0
  while 1
    let ucs = char2nr(substitute(str, mx_first, '\1', ''))
    if ucs == 0
      break
    endif
    let width = width + s:wcwidth(ucs)
    let str = substitute(str, mx_first, '', '')
  endwhile
  return width
endfunction

function! s:truncate(str, num)
  let mx_first = '^\(.\)\(.*\)$'
  let str = a:str
  let ret = ''
  let width = 0
  while 1
    let char = substitute(str, mx_first, '\1', '')
    let ucs = char2nr(char)
    if ucs == 0
      break
    endif
    let cells = s:wcwidth(ucs)
    if width + cells > a:num
      break
    endif
    let width = width + cells
    let ret .= char
    let str = substitute(str, mx_first, '\2', '')
  endwhile
  while width + 1 <= a:num
    let ret .= " "
    let width = width + 1
  endwhile
  return ret
endfunction

function! s:nr2byte(nr)
  if a:nr < 0x80
    return nr2char(a:nr)
  elseif a:nr < 0x800
    return nr2char(a:nr/64+192).nr2char(a:nr%64+128)
  else
    return nr2char(a:nr/4096%16+224).nr2char(a:nr/64%64+128).nr2char(a:nr%64+128)
  endif
endfunction

function! s:nr2enc_char(charcode)
  if &encoding == 'utf-8'
    return nr2char(a:charcode)
  endif
  let char = s:nr2byte(a:charcode)
  if strlen(char) > 1
    let char = strtrans(iconv(char, 'utf-8', &encoding))
  endif
  return char
endfunction

function! s:nr2hex(nr)
  let n = a:nr
  let r = ""
  while n
    let r = '0123456789ABCDEF'[n % 16] . r
    let n = n / 16
  endwhile
  return r
endfunction

function! s:encodeURIComponent(instr)
  let instr = iconv(a:instr, &enc, "utf-8")
  let len = strlen(instr)
  let i = 0
  let outstr = ''
  while i < len
    let ch = instr[i]
    if ch =~# '[0-9A-Za-z-._~!''()*]'
      let outstr .= ch
    elseif ch == ' '
      let outstr .= '+'
    else
      let outstr .= '%' . substitute('0' . s:nr2hex(char2nr(ch)), '^.*\(..\)$', '\1', '')
    endif
    let i = i + 1
  endwhile
  return outstr
endfunction

function! s:decodeEntityReference(str)
  let str = a:str
  let str = substitute(str, '&gt;', '>', 'g')
  let str = substitute(str, '&lt;', '<', 'g')
  let str = substitute(str, '&quot;', '"', 'g')
  let str = substitute(str, '&apos;', "'", 'g')
  let str = substitute(str, '&nbsp;', ' ', 'g')
  let str = substitute(str, '&yen;', '\&#65509;', 'g')
  let str = substitute(str, '&#\(\d\+\);', '\=s:nr2enc_char(submatch(1))', 'g')
  let str = substitute(str, '&amp;', '\&', 'g')
  return str
endfunction

function! s:item2query(items, sep)
  let ret = ''
  if type(a:items) == 4
    for key in keys(a:items)
      if strlen(ret) | let ret .= a:sep | endif
      let ret .= key . "=" . s:encodeURIComponent(a:items[key])
    endfor
  elseif type(a:items) == 3
    for item in a:items
      if strlen(ret) | let ret .= a:sep | endif
      let ret .= item
    endfor
  else
    let ret = a:items
  endif
  return ret
endfunction

function! s:doHttp(url, getdata, postdata, headdata, returnheader)
  let url = a:url
  let getdata = s:item2query(a:getdata, '&')
  let postdata = s:item2query(a:postdata, '&')
  if strlen(getdata)
    let url .= "?" . getdata
  endif
  let command = "curl -L -s -k"
  if a:returnheader
    let command .= " -i"
  endif
  let quote = &shellxquote == '"' ?  "'" : '"'
  for key in keys(a:headdata)
    let command .= " -H " . quote . key . ": " . a:headdata[key] . quote
  endfor
  let command .= " \"" . url . "\""
  if strlen(postdata)
    let file = tempname()
    call writefile([postdata], file)
    let res = system(command . " -d @" . quote.file.quote)
    call delete(file)
  else
    let res = system(command)
  endif
  return res
endfunction

function! s:FormatEntry(str)
  let mx_id = '^.*<id[^>]*>\(.*\)</id>.*$'
  let mx_source = '^\(.*\)<source[^>]*>\(.*\)</source>\(.*\)$'
  let mx_url = '^.*<link rel="alternate" href="\([^"]\+\)".*$'
  let mx_title = '^.*<title[^>]*>\(.*\)</title>.*$'
  let mx_content = '^.*<content[^>]*>\(.*\)</content>.*$'
  let mx_summary = '^.*<summary[^>]*>\(.*\)</summary>.*$'
  let mx_author = '^.*<author[^>]*><name[^>]*>\([^<]*\)</name></author>.*$'
  let mx_published = '^.*<published>\([^<]*\)</published>.*$'
  let mx_readed = '^.*<category.\{-} label="read"/>.*$'
  let mx_starred = '^.*<category.\{-} label="starred"/>.*$'

  let str = substitute(a:str, mx_source, '\1\3', '')

  let id = substitute(matchstr(str, mx_id), mx_id, '\1', '')
  let id = s:decodeEntityReference(id)

  let url = substitute(matchstr(str, mx_url), mx_url, '\1', '')
  let url = s:decodeEntityReference(url)

  let author = substitute(matchstr(str, mx_author), mx_author, '\1', '')
  let author = s:decodeEntityReference(author)

  let published = substitute(matchstr(str, mx_published), mx_published, '\1', '')

  let title = substitute(matchstr(str, mx_title), mx_title, '\1', '')
  let title = substitute(title, '^<!\[CDATA\[\(.*\)\]\]>$', '\1', 'g')
  let title = s:decodeEntityReference(title)
  let title = substitute(title, '<[^>]\+>', '', 'g')
  let title = s:decodeEntityReference(title)

  let source = substitute(a:str, mx_source, '\2', '')
  let source = substitute(source, mx_title, '\1', '')
  let source = substitute(source, '^<!\[CDATA\[\(.*\)\]\]>$', '\1', 'g')
  let source = s:decodeEntityReference(source)
  let source = substitute(source, '<[^>]\+>', '', 'g')
  let source = s:decodeEntityReference(source)

  let content = substitute(matchstr(str, mx_content), mx_content, '\1', '')
  if len(content) == 0
    let content = substitute(matchstr(str, mx_summary), mx_summary, '\1', '')
  endif
  let content = substitute(content, '^<!\[CDATA\[\(.*\)\]\]>$', '\1', 'g')
  let content = s:decodeEntityReference(content)
  let content = substitute(content, '\(<br[^>]*>\|<p[^>]*>\|</p[^>]*>\)', "\r", 'g')
  let content = substitute(content, '<[^>]\+>', '', 'g')
  let content = substitute(content, '^ *', '', '')
  let content = s:decodeEntityReference(content)

  let readed = len(matchstr(str, mx_readed)) > 0 ? 1 : 0
  let starred = len(matchstr(str, mx_starred)) > 0 ? 1 : 0

  return {"id": id, "title": title, "source": source, "url": url, "content": content, "author": author, "published": published, "readed": readed, "starred": starred}
endfunction

function! s:SetStarred(sid, auth, token, id, star)
  if a:star
    let opt = {'a': 'user/-/state/com.google/starred', 'ac': 'edit-tags', 'i': a:id, 's': 'user/-/state/com.google/reading-list', 'T': a:token}
  else
    let opt = {'r': 'user/-/state/com.google/starred', 'ac': 'edit-tags', 'i': a:id, 's': 'user/-/state/com.google/reading-list', 'T': a:token}
  endif
  return s:doHttp("https://www.google.com/reader/api/0/edit-tag", {}, opt, {"Cookie": "SID=".a:sid, "Authorization": "GoogleLogin auth=".a:auth}, 0)
endfunction

function! s:SetReaded(sid, auth, token, id, readed)
  if a:readed
    let opt = {'a': 'user/-/state/com.google/read', 'ac': 'edit-tags', 'i': a:id, 's': 'user/-/state/com.google/reading-list', 'r': 'user/-/state/com.google/kept-unread', 'T': a:token}
  else
    let opt = {'a': 'user/-/state/com.google/kept-unread', 'ac': 'edit-tags', 'i': a:id, 's': 'user/-/state/com.google/reading-list', 'r': 'user/-/state/com.google/read', 'T': a:token}
  endif
  return s:doHttp("https://www.google.com/reader/api/0/edit-tag", {}, opt, {"Cookie": "SID=".a:sid, "Authorization": "GoogleLogin auth=".a:auth}, 0)
endfunction

function! s:GetEntries(email, passwd, opt)
  if !exists("s:sid")
    let ret = split(s:doHttp("https://www.google.com/accounts/ClientLogin", {}, {"accountType": "HOSTED_OR_GOOGLE", "Email": a:email, "Passwd": a:passwd, "source": "googlereader.vim", "service": "reader"}, {}, 0), "\n")
	let s:sid = substitute(ret[0], "^SID=", "", "")
	let s:auth = substitute(ret[2], "^Auth=", "", "")
  endif
  if !exists("s:token")
    let s:token = s:doHttp("https://www.google.com/reader/api/0/token", {"client": "googlereader.vim", "ck": localtime()*1000}, {}, {"Cookie": "SID=".s:sid, "Authorization": "GoogleLogin auth=".s:auth}, 0)
  endif
  if s:sid == '' || s:sid =~ '^Error=BadAuthentication'
    echoerr "GoogleReader: bad authentication"
    let s:sid = ''
    return []
  endif

  if !has_key(a:opt, "n")
    let a:opt["n"] = 50
  endif
  if !has_key(a:opt, "xt")
    let a:opt["xt"] = "user/-/state/com.google/read"
  endif
  let a:opt["ck"] = localtime()*1000
  let opt = copy(a:opt)
  if len(opt["xt"]) == 0
    call remove(opt, "xt")
  endif
  let feed = s:doHttp("https://www.google.com/reader/atom/user/-/state/com.google/reading-list", opt, {}, {"Cookie": "SID=".s:sid."; T=".s:token, "Authorization": "GoogleLogin auth=".s:auth}, 0)
  let feed = iconv(feed, "utf-8", &encoding)
  let feed = substitute(feed, '<', "\r<", 'g')
  let feed = substitute(feed, '\(<entry[^>]*>.\{-}</entry>\)', '\=substitute(submatch(1), "[\r\n]", "", "g")', 'g')
  let feed = substitute(feed, '>\s*<', '><', 'g')
  return map(filter(split(feed, "\r"), 'v:val =~ "^<entry"'), 's:FormatEntry(v:val)')
endfunction

function! s:ShowEntry()
  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr > 0 && winnr != winnr()
    execute winnr.'wincmd w'
  endif

  let str = getline('.')
  let mx_row_mark = '^\(\d\+\)\(: \)\([\* ]\)\([U ]\)\( .*\)'
  let row = str2nr(substitute(matchstr(str, mx_row_mark), mx_row_mark, '\1', '')) - 1
  let starred = substitute(matchstr(str, mx_row_mark), mx_row_mark, '\3', '')
  let readed = substitute(matchstr(str, mx_row_mark), mx_row_mark, '\4', '')

  let bufname = s:CONTENT_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    if bufname('%').'X' ==# 'X' && &modified == 0
      silent! edit `=bufname`
    else
      let height = winheight('.') * 7 / 10
      silent! exec 'belowright '.height.'new `=bufname`'
    endif
  else
    if winnr != winnr()
      execute winnr.'wincmd w'
    endif
  endif
  setlocal buftype=nofile bufhidden=hide noswapfile wrap ft= nonumber modifiable nolist
  silent! %d _
  redraw!

  let entry = s:entries[row]
  if readed == 'U'
    call s:ToggleReaded()
  endif

  call setline(1, printf("Source: %s", entry['source']))
  call setline(2, printf("Title: %s", entry['title']))
  call setline(3, printf("URL: %s", entry['url']))
  call setline(4, printf("Publish: %s", entry['published']))
  call setline(5, printf("Author: %s", entry['author']))
  call setline(6, "---------------------------------------------")
  normal! G
  call setline(7, entry['content'])
  silent! %s/\r/\r/g
  setlocal nomodifiable
  syntax match SpecialKey /^\(Source\|Title\|URL\|Publish\|Author\):/he=e-1
  nnoremap <silent> <buffer> <space> <c-d>
  nnoremap <silent> <buffer> q :bw!<cr>
  exec 'nnoremap <silent> <buffer> <c-p> :call <SID>ShowPrevEntry()<cr>'
  exec 'nnoremap <silent> <buffer> <c-n> :call <SID>ShowNextEntry()<cr>'
  exec 'nnoremap <silent> <buffer> <c-i> :call <SID>ShowEntryInBrowser()<cr>'
  exec 'nnoremap <silent> <buffer> +     :call <SID>ToggleReaded()<cr>'
  exec 'nnoremap <silent> <buffer> *     :call <SID>ToggleStarred()<cr>'
  exec 'nnoremap <silent> <buffer> ?     :call <SID>Help()<cr>'
  let b:id = entry['id']
  let b:url = entry['url']
  let b:readed = entry['readed']
  normal! gg
endfunction

function! s:ShowEntryInBrowser()
  let bufname = s:CONTENT_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    return
  endif
  if winnr != winnr()
    execute winnr.'wincmd w'
  endif

  if has('win32')
    silent! exec "!start rundll32 url.dll,FileProtocolHandler ".escape(b:url ,'#')
  elseif has('mac')
    silent! exec "!open '".escape(b:url ,'#')."'"
  else
    call system("x-www-browser '".b:url."' 2>&1 > /dev/null &")
  endif
  redraw!
endfunction

function! s:ShowPrevEntry()
  let bufname = s:CONTENT_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    return
  endif
  if winnr != winnr()
    execute winnr.'wincmd w'
  endif

  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr > 0 && winnr != winnr()
    execute winnr.'wincmd w'
    normal! k
    call s:ShowEntry()
  endif
endfunction

function! s:ShowNextEntry()
  let bufname = s:CONTENT_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    return
  endif
  if winnr != winnr()
    execute winnr.'wincmd w'
  endif

  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr > 0 && winnr != winnr()
    execute winnr.'wincmd w'
    normal! j
    call s:ShowEntry()
  endif
endfunction

function! s:ToggleStarred()
  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  let oldwinnr = winnr()
  if winnr > 0 && winnr != oldwinnr
    execute winnr.'wincmd w'
  endif

  let str = getline('.')
  let mx_row_mark = '^\(\d\+\)\(: \)\([\* ]\)\([U ]\)\( .*\)'
  let row = str2nr(substitute(matchstr(str, mx_row_mark), mx_row_mark, '\1', '')) - 1
  let starred = substitute(matchstr(str, mx_row_mark), mx_row_mark, '\3', '')
  let readed = substitute(matchstr(str, mx_row_mark), mx_row_mark, '\4', '')
  let entry = s:entries[row]
  if s:SetStarred(s:sid, s:auth, s:token, entry['id'], (starred == '*' ? 0 : 1)) == "OK"
    let str = substitute(matchstr(str, mx_row_mark), mx_row_mark, '\1\2'.(starred == '*' ? ' ' : '*').readed.'\5', '')
    let oldmodifiable = &l:modifiable
    setlocal modifiable
    call setline(line('.'), str)
    let &l:modifiable = oldmodifiable
  else
    echoerr "GoogleReader: failed to mark star or unstar"
  endif
  if winnr > 0 && winnr != oldwinnr
    wincmd p
  endif
endfunction

function! s:ToggleReaded()
  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  let oldwinnr = winnr()
  if winnr > 0 && winnr != oldwinnr
    execute winnr.'wincmd w'
  endif

  let str = getline('.')
  let mx_row_mark = '^\(\d\+\)\(: \)\([\* ]\)\([U ]\)\( .*\)'
  let row = str2nr(substitute(matchstr(str, mx_row_mark), mx_row_mark, '\1', '')) - 1
  let starred = substitute(matchstr(str, mx_row_mark), mx_row_mark, '\3', '')
  let readed = substitute(matchstr(str, mx_row_mark), mx_row_mark, '\4', '')
  let entry = s:entries[row]
  if s:SetReaded(s:sid, s:auth, s:token, entry['id'], (readed == 'U' ? 1 : 0)) == "OK"
    let str = substitute(matchstr(str, mx_row_mark), mx_row_mark, '\1\2'.starred.(readed == 'U' ? ' ' : 'U').'\5', '')
    let oldmodifiable = &l:modifiable
    setlocal modifiable
    call setline(line('.'), str)
    let &l:modifiable = oldmodifiable
  endif
  if winnr > 0 && winnr != oldwinnr
    wincmd p
  endif
endfunction

function! s:ShowEntries(opt)
  if exists("g:googlereader_email")
    let email = g:googlereader_email
  else
    let email = input('GoogleReader email:')
  endif
  if exists("g:googlereader_passwd")
    let passwd = g:googlereader_passwd
  else
    let passwd = inputsecret('GoogleReader password:')
  endif
    
  if len(email) == 0 || len(passwd) == 0
    echohl WarningMsg
    echo "authentication required for GoogleReader."
    echohl None
    return
  end

  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    if &modified == 0
      silent! edit `=bufname`
    else
      silent! belowright new `=bufname`
    endif
  else
    if winnr != winnr()
      execute winnr.'wincmd w'
    endif
  endif
  setlocal buftype=nofile bufhidden=hide noswapfile nowrap ft= nonumber modifiable cursorline
  silent! %d _
  redraw!

  if !exists('b:xt')
    let b:xt = 'user/-/state/com.google/read'
  endif
  if !has_key(a:opt, 'xt')
    let a:opt['xt'] = b:xt
  endif
  let b:xt = a:opt['xt']
  if len(a:opt['xt'])
    echo "reading unread entries..."
  else
    echo "reading full entries..."
  endif
  let s:entries = s:GetEntries(email, passwd, a:opt)
  let cnt = 1
  for l:entry in s:entries
    let source = s:truncate(l:entry['source'], 20)
    call setline(cnt, printf("%03d: %s%s %s %s", cnt, (l:entry['starred'] == 1 ? '*' : ' '), (l:entry['readed'] == 1 ? ' ' : 'U'), source, l:entry['title']))
    let cnt = cnt + 1
  endfor
  setlocal nomodifiable
  syntax match SpecialKey /^\d\+:/he=e-1
  exec 'nnoremap <silent> <buffer> <cr>  :call <SID>ShowEntry()<cr>'
  exec 'nnoremap <silent> <buffer> r     :call <SID>ShowEntries({})<cr>'
  exec 'nnoremap <silent> <buffer> <s-a> :call <SID>ShowEntries({"xt": "user/-/state/com.google/read"})<cr>'
  exec 'nnoremap <silent> <buffer> <c-a> :call <SID>ShowEntries({"xt": ""})<cr>'
  exec 'nnoremap <silent> <buffer> +     :call <SID>ToggleReaded()<cr>'
  exec 'nnoremap <silent> <buffer> *     :call <SID>ToggleStarred()<cr>'
  exec 'nnoremap <silent> <buffer> ?     :call <SID>Help()<cr>'
  nnoremap <silent> <buffer> <c-n> j
  nnoremap <silent> <buffer> <c-p> k
  nnoremap <silent> <buffer> q :bw!<cr>
  normal! gg
  redraw!
  echo ""
endfunction

function! s:Help()
  echohl None
  echo 'GoogleReader.vim version ' . g:googlereader_vim_version
  echohl Title
  echo '[LIST]'
  echohl SpecialKey
  echo '<c-n>     : goto next and open entry'
  echo '<c-p>     : goto prev and open entry'
  echo '<cr>      : show the entry'
  echo '<c-a>     : show all list'
  echo '<s-a>     : show unread list'
  echo '+         : toggle read/unread mark'
  echo '*         : toggle star/unstar mark'
  echo 'r         : reload entries'
  echo 'q         : close window'
  echohl Title
  echo '[CONTENT]'
  echohl SpecialKey
  echo '<c-n>     : show next entry'
  echo '<c-p>     : show prev entry'
  echo '<c-i>     : open URL with browser'
  echo 'q         : close window'
  echohl MoreMsg
  echo "[Hit any key]"
  echohl None
  call getchar()
  redraw!
endfunction

function! s:GoogleReader()
  call s:ShowEntries({"xt": ""})
endfunction

command! GoogleReader call s:GoogleReader()

" vim:set et

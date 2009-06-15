"=============================================================================
" File: googlereader.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 15-Jun-2009.
" Version: 0.5
" WebPage: http://github.com/mattn/googlereader-vim/tree/master
" Usage:
"
"   :GoogleReader
"
" GetLatestVimScripts: 2678 1 :AutoInstall: googlereader.vim

if !executable('curl')
  finish
endif

let s:LIST_BUFNAME = '==GoogleReader List=='
let s:CONTENT_BUFNAME = '==GoogleReader Content=='

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
  if has('iconv') && strlen(char) > 1
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
      let outstr = outstr . ch
    elseif ch == ' '
      let outstr = outstr . '+'
    else
      let outstr = outstr . '%' . substitute('0' . s:nr2hex(char2nr(ch)), '^.*\(..\)$', '\1', '')
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

function! s:WebAccess(url, getdata, postdata, cookie)
  let url = a:url
  let getdata = ''
  for key in keys(a:getdata)
    if len(getdata)
	  let getdata .= "&"
    endif
    let getdata = getdata . key . "=" . s:encodeURIComponent(a:getdata[key])
  endfor
  if len(getdata)
    let url = a:url . "?" . getdata
  endif
  let postdata = ''
  for key in keys(a:postdata)
    let postdata = postdata . " -d " . key . "=" . s:encodeURIComponent(a:postdata[key])
  endfor
  let cookie = ''
  for key in keys(a:cookie)
    let cookie = cookie . " -b " . key . "=" . s:encodeURIComponent(a:cookie[key])
  endfor
  return system("curl -s -k " . postdata . cookie . " \"" . url . "\"")
endfunction

function! s:GetSID(email, passwd)
  return substitute(s:WebAccess("https://www.google.com/accounts/ClientLogin", {}, {"Email": a:email, "Passwd": a:passwd, "source": "googlereader.vim", "service": "reader"}, {}), '^SID=\([^\x0a]*\).*', '\1', '')
endfunction

function! s:GetToken(sid)
  return s:WebAccess("http://www.google.com/reader/api/0/token", {}, {}, {"SID": a:sid})
endfunction

function! s:FormatEntry(str)
  let mx_id = '^\(.*\)<id[^>]*>\(.*\)</id>\(.*\)$'
  let mx_source = '^\(.*\)<source[^>]*>\(.*\)</source>\(.*\)$'
  let mx_url = '^.*<link rel="alternate" href="\([^"]\+\)".*$'
  let mx_title = '^.*<title[^>]*>\(.*\)</title>.*$'
  let mx_content = '^.*<content[^>]*>\(.*\)</content>.*$'
  let mx_summary = '^.*<summary[^>]*>\(.*\)</summary>.*$'
  let mx_author = '^.*<author[^>]*><name[^>]*>\([^<]*\)</name></author>.*$'
  let mx_published = '^.*<published>\([^<]*\)</published>.*$'
  let mx_readed = '^.*<category.\{-} label="read"/>.*$'

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

  return {"id": id, "title": title, "source": source, "url": url, "content": content, "author": author, "published": published, "readed": readed}
endfunction

function! s:SetReaded(id)
  if !exists("s:sid")
    let s:sid = s:GetSID(g:googlereader_email, g:googlereader_passwd)
  endif
  if !exists("s:token")
    let s:token = s:GetToken(s:sid)
  endif
" not implemented
"
"    EDIT_TAG_ARGS = {
"        'feed' : 's',
"        'entry' : 'i',
"        'add' : 'a',
"        'remove' : 'r',
"        'action' : 'edit-tags',
"        'token' : s:token,
"        }
"  return s:WebAccess("http://www.google.com/reader/api/0/edit-tag", {}, {}, {"SID": a:sid})
endfunction

function! s:GetEntries(email, passwd, opt)
  if !exists("s:sid")
    let s:sid = s:GetSID(a:email, a:passwd)
  endif
  if !exists("s:token")
    let s:token = s:GetToken(s:sid)
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
  let feed = s:WebAccess("http://www.google.com/reader/atom/user/-/state/com.google/reading-list", opt, {}, {"SID": s:sid, "T": s:token})
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

  let row = str2nr(substitute(getline('.'), '^\(\d\+\).*', '\1', ''))-1

  let bufname = s:CONTENT_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    if bufname('%').'X' ==# 'X' && &modified == 0
      silent! edit `=bufname`
    else
      silent! belowright 15new `=bufname`
    endif
  else
    if winnr != winnr()
      execute winnr.'wincmd w'
    endif
  endif
  setlocal buftype=nofile bufhidden=hide noswapfile nowrap ft= nowrap nonumber modifiable
  silent! %d _
  let entry = s:entries[row]
  call setline(1, printf("Source: %s", entry['source']))
  call setline(2, printf("Title: %s", entry['title']))
  call setline(3, printf("URL: %s", entry['url']))
  call setline(4, printf("Publish: %s", entry['published']))
  call setline(5, printf("Author: %s", entry['author']))
  call setline(6, "---------------------------------------------")
  normal! G
  call setline(7, entry['content'])
  silent! %s/\r/\r/g
  silent! normal! 7GVGgq
  setlocal nomodifiable
  syntax match SpecialKey /^\(Source\|Title\|URL\|Publish\|Author\):/he=e-1
  nnoremap <silent> <buffer> <space> <c-d>
  nnoremap <silent> <buffer> q :bw!<cr>
  exec 'nnoremap <silent> <buffer> <cr> :call <SID>ShowEntry()<cr>'
  exec 'nnoremap <silent> <buffer> <c-p> :call <SID>ShowPrevEntry()<cr>'
  exec 'nnoremap <silent> <buffer> <c-n> :call <SID>ShowNextEntry()<cr>'
  exec 'nnoremap <silent> <buffer> <c-i> :call <SID>ShowEntryInBrowser()<cr>'
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

  let url = s:entries[b:url]
  if has('win32')
    silent! exec "!start rundll32 url.dll,FileProtocolHandler ".substitute(url,'#', '\\#', '')
  else
    system("firefox '".url."' 2>&1 > /dev/null &")
  endif
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
  let g:hoge = winnr
  if winnr < 1
    return
  endif
  let g:hoge = winnr
  if winnr != winnr()
    execute winnr.'wincmd w'
  endif
  let g:hoge = 'foo'

  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr > 0 && winnr != winnr()
    execute winnr.'wincmd w'
	normal! j
	call s:ShowEntry()
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
    finish
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
  if !exists('b:xt')
    let b:xt = 'user/-/state/com.google/read'
  endif
  if !has_key(a:opt, 'xt')
    let a:opt['xt'] = b:xt
  endif
  let b:xt = a:opt['xt']
  setlocal buftype=nofile bufhidden=hide noswapfile nowrap ft= nowrap nonumber cursorline modifiable
  silent! %d _
  redraw!

  if len(a:opt['xt'])
    echo "reading unread entries..."
  else
    echo "reading full entries..."
  endif
  let s:entries = s:GetEntries(email, passwd, a:opt)
  let cnt = 1
  for l:entry in s:entries
    call setline(cnt, printf("%03d: %s %s %s", cnt, (l:entry['readed'] == 1 ? ' ' : 'U'), l:entry['source'], l:entry['title']))
    let cnt = cnt + 1
  endfor
  setlocal nomodifiable
  syntax match SpecialKey /^\d\+:/he=e-1
  exec 'nnoremap <silent> <buffer> <cr> :call <SID>ShowEntry()<cr>'
  exec 'nnoremap <silent> <buffer> r :call <SID>ShowEntries({})<cr>'
  exec 'nnoremap <silent> <buffer> <s-a> :call <SID>ShowEntries({"xt": "user/-/state/com.google/read"})<cr>'
  exec 'nnoremap <silent> <buffer> <c-a> :call <SID>ShowEntries({"xt": ""})<cr>'
  nnoremap <silent> <buffer> <c-n> j
  nnoremap <silent> <buffer> <c-p> k
  nnoremap <silent> <buffer> q :bw!<cr>
  normal! gg
  redraw!
  echo ""
endfunction

command! GoogleReader call s:ShowEntries({"xt": ""})

" vim:set et

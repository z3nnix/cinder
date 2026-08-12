#!/usr/bin/env ruby

require 'fileutils'
require 'pathname'
require 'cgi'

class MDParser
  def initialize(docs_dir = 'docs', output_dir = 'docs_html')
    @docs_dir = docs_dir
    @output_dir = output_dir
    @files = []
    @site_title = "Cinder by Example"
    @site_description = "Cinder is small programming language for low-level development."
    @github_url = "https://github.com/z3nnix/cinder"
  end

  def parse_all
    Dir.chdir(@docs_dir) do
      @files = Dir.glob('*.md').sort.reject { |f| f == 'README.md' }
    end
    @files.sort_by! { |f| f.match(/^(\d+)/)&.captures&.first&.to_i || 0 }

    FileUtils.mkdir_p(@output_dir)
    create_css

    @files.each { |f| parse_file(f) }
    generate_index

    puts ":: Site generated #{@output_dir}"
    puts ":: Page generated - #{@files.size + 1}"
  end

  private

  def parse_file(filename)
    @current_file = filename
    content = File.read(File.join(@docs_dir, filename), encoding: 'UTF-8')
    title = extract_title(content)
    html = parse_markdown(content)
    prev, nxt = adjacent_files(filename)
    output = build_page(title, html, filename, prev, nxt)
    File.write(File.join(@output_dir, filename.sub('.md', '.html')), output, encoding: 'UTF-8')
  end

  def extract_title(content)
    content =~ /^#\s+(.+)$/ ? $1.strip : File.basename(@current_file, '.md')
  end

  def adjacent_files(filename)
    idx = @files.index(filename)
    [idx && idx > 0 ? @files[idx-1] : nil,
     idx && idx < @files.length-1 ? @files[idx+1] : nil]
  end

  IDENT_RE = '[a-zA-Z_][a-zA-Z0-9_]*'
  RE_STR_DQ_SQ = /"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'/
  RE_STR_RUST = /(?:[rbc])?"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)'/
  RE_COMMENT_C = /\/\/[^\n]*|\/\*[\s\S]*?\*\//
  RE_COMMENT_SHELL = /#[^\n]*/
  RE_COMMENT_GAS = /#[^\n]*|\/\*[\s\S]*?\*\//
  RE_COMMENT_LD = /\/\*[\s\S]*?\*\//
  RE_NUM = /(?<![a-zA-Z0-9_])(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*)(?:\.\d[\d_]*(?:[eE][+-]?\d+)?)?(?:u(?:8|16|32|64|128)|i(?:8|16|32|64|128)|f(?:32|64)|usize|isize)?/
  RE_NUM_LD = /(?<![a-zA-Z0-9_])(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*)(?:\.\d[\d_]*(?:[eE][+-]?\d+)?)?(?:[KM]|u(?:8|16|32|64|128)|i(?:8|16|32|64|128)|f(?:32|64)|usize|isize)?/
  HIGHLIGHT_CLASSES = {
    comment: 'hljs-comment',
    string: 'hljs-string',
    number: 'hljs-number',
    keyword: 'hljs-keyword',
    type: 'hljs-type',
    meta: 'hljs-meta',
    directive: 'hljs-meta',
    symbol: 'hljs-symbol',
    label: 'hljs-symbol',
    variable: 'hljs-variable',
    register: 'hljs-variable',
    immediate: 'hljs-variable',
    built_in: 'hljs-built_in',
    call: 'hljs-title function_',
  }

  def hl_regex(keywords: [], types: [], comment:, strings:, num_re: RE_NUM.source, extra: {}, built_in: "\\.#{IDENT_RE}")
    parts = []
    parts << "(?<comment>#{comment})"
    parts << "(?<string>#{strings})"
    extra.each { |name, pat| parts << "(?<#{name}>#{pat})" }
    parts << "(?<number>#{num_re})"
    parts << "(?<keyword>\\b(?:#{keywords.join('|')})\\b)" if keywords.any?
    parts << "(?<type>\\b(?:#{types.join('|')})\\b)" if types.any?
    parts << "(?<call>#{IDENT_RE})(?=\\s*\\()"
    parts << "(?<built_in>#{built_in})" if built_in
    Regexp.new(parts.join('|'))
  end

  def code_highlighters
    @code_highlighters ||= begin
      rust_keywords = %w[
        as break const continue defer else enum extern fn for if let loop mut
        return switch unsafe use while volatile static struct export sizeof
        alignof offsetof static_assert true false none null
      ]
      rust_types = %w[u8 u16 u32 u64 u128 i8 i16 i32 i64 i128 f32 f64 bool usize isize void]
      shell_keywords = %w[
        if then else elif fi for while do done case esac in function return
        local export exit echo cd set shift unset readonly test
      ]
      gas_keywords = %w[
        mov movb movw movl movq movabs add addb addw addl addq sub subb subw subl
        subq imul mul div idiv inc dec neg not and or xor test cmp lea push pop
        call ret jmp je jne jz jnz jg jge jl jle jb jbe ja jae jo jno js jns jc
        jnc int syscall sysenter nop hlt cli sti lock repnz rep ud2
      ]
      ld_keywords = %w[
        ENTRY OUTPUT_FORMAT OUTPUT_ARCH OUTPUT SECTIONS PHDRS MEMORY KEEP ALIGN
        PROVIDE HIDDEN SIZEOF ADDR LOADADDR MAXPAGESIZE COMMON ASSERT
      ]
      label_re = "\\b#{IDENT_RE}:"
      register_re = '%[a-zA-Z][a-zA-Z0-9]*'
      directive_re = "\\.#{IDENT_RE}"

      {
        'rust' => {
          regex: hl_regex(keywords: rust_keywords, types: rust_types,
                          comment: RE_COMMENT_C.source,
                          strings: RE_STR_RUST.source),
        },
        'bash' => {
          regex: hl_regex(keywords: shell_keywords,
                          comment: RE_COMMENT_SHELL.source,
                          strings: RE_STR_DQ_SQ.source,
                          extra: { variable: "\\$#{IDENT_RE}" },
                          built_in: nil),
        },
        'sh' => {
          regex: hl_regex(keywords: shell_keywords,
                          comment: RE_COMMENT_SHELL.source,
                          strings: RE_STR_DQ_SQ.source,
                          extra: { variable: "\\$#{IDENT_RE}" },
                          built_in: nil),
        },
        'gas' => {
          regex: hl_regex(keywords: gas_keywords,
                          comment: RE_COMMENT_GAS.source,
                          strings: RE_STR_DQ_SQ.source,
                          extra: {
                            directive: directive_re,
                            register: register_re,
                            immediate: '\\$[a-zA-Z0-9_]+',
                            label: label_re,
                          },
                          built_in: nil),
        },
        'ld' => {
          regex: hl_regex(keywords: ld_keywords,
                          comment: RE_COMMENT_LD.source,
                          strings: RE_STR_DQ_SQ.source,
                          num_re: RE_NUM_LD.source),
        },
      }
    end
  end

  def highlight_code(code, lang)
    hl = code_highlighters[lang.to_s.strip.downcase]
    return CGI.escape_html(code) unless hl
    regex = hl[:regex]
    html = +''
    pos = 0
    code.scan(regex) do
      m = Regexp.last_match
      html << CGI.escape_html(code[pos...m.begin(0)])
      html << render_highlight_match(m, regex)
      pos = m.end(0)
    end
    html << CGI.escape_html(code[pos..])
  end

  def render_highlight_match(m, regex)
    HIGHLIGHT_CLASSES.each do |name, cls|
      next unless regex.names.include?(name.to_s)
      val = m[name]
      next if val.nil?
      return "<span class=\"#{cls}\">#{CGI.escape_html(val)}</span>"
    end
    CGI.escape_html(m[0])
  end

  def parse_markdown(content)
    lines = content.lines.map(&:rstrip)
    result = []
    in_code = false
    code_lang = ''
    code_lines = []
    in_table = false
    table_rows = []
    table_align = []
    in_list = false
    list_items = []
    in_blockquote = false
    bq_lines = []

    i = 0
    while i < lines.length
      line = lines[i]

      if line =~ /^```(\w*)$/
        if in_code
          code = code_lines.join("\n")
          result << "<pre><code class=\"language-#{code_lang}\">#{highlight_code(code, code_lang)}</code></pre>"
          code_lines.clear
          in_code = false
          code_lang = ''
        else
          in_code = true
          code_lang = $1 || ''
        end
        i += 1
        next
      end
      if in_code
        code_lines << line
        i += 1
        next
      end

      if !in_table && line =~ /^\|.*\|$/ && i+1 < lines.length && lines[i+1] =~ /^\|[\s\-:|]+\|$/
        in_table = true
        table_rows = []
        table_align = []

        header = line.split('|').map(&:strip).reject(&:empty?)
        table_rows << header

        align_line = lines[i+1].split('|').map(&:strip).reject(&:empty?)
        table_align = align_line.map do |cell|
          if cell =~ /^:.*:$/ then 'center'
          elsif cell =~ /^:.*/  then 'left'
          elsif cell =~ /.*:$/  then 'right'
          else 'left'
          end
        end
        i += 2

        while i < lines.length && lines[i] =~ /^\|.*\|$/
          row = lines[i].split('|').map(&:strip).reject(&:empty?)
          table_rows << row if row.any?
          i += 1
        end

        result << render_table(table_rows, table_align)
        in_table = false
        next
      end

      
      if line =~ /^(#+)\s+(.+)$/
        level = $1.length
        title = $2.strip
        anchor = title.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
        result << "<h#{level} id=\"#{anchor}\">#{parse_inline(title)}</h#{level}>"
        i += 1
        next
      end

      if line =~ /^>\s*(.*)$/
        in_blockquote = true
        bq_lines << $1
        i += 1
        next
      elsif in_blockquote && line.empty?
        result << "<blockquote>#{parse_inline(bq_lines.join(' '))}</blockquote>"
        bq_lines.clear
        in_blockquote = false
        i += 1
        next
      elsif in_blockquote
        bq_lines << line
        i += 1
        next
      end

      if line =~ /^(\s*)([-*+])\s+(.+)$/
        indent = $1.length
        list_items << { indent: indent, content: $3, type: :unordered }
        in_list = true
        i += 1
        next
      elsif line =~ /^(\s*)(\d+)\.\s+(.+)$/
        indent = $1.length
        list_items << { indent: indent, content: $3, type: :ordered }
        in_list = true
        i += 1
        next
      elsif in_list && line.empty?
        result << render_list(list_items)
        list_items.clear
        in_list = false
        i += 1
        next
      elsif in_list && line !~ /^(\s*)([-*+]|\d+\.)\s+/
        if list_items.any?
          list_items.last[:content] += "\n" + line
        end
        i += 1
        next
      end

      if in_list
        result << render_list(list_items)
        list_items.clear
        in_list = false
      end

      if line =~ /^[-*_]{3,}$/
        result << "<hr>"
        i += 1
        next
      end

      unless line.empty?
        result << "<p>#{parse_inline(line)}</p>"
      end
      i += 1
    end

    if in_code
      code = code_lines.join("\n")
      result << "<pre><code class=\"language-#{code_lang}\">#{highlight_code(code, code_lang)}</code></pre>"
    end
    if in_list && list_items.any?
      result << render_list(list_items)
    end
    if in_blockquote && bq_lines.any?
      result << "<blockquote>#{parse_inline(bq_lines.join(' '))}</blockquote>"
    end

    result.join("\n")
  end

  def render_table(rows, align)
    return '' if rows.empty?
    header = rows.shift
    html = "<table>\n<thead>\n<tr>"
    header.each_with_index do |cell, idx|
      align_attr = align[idx] ? " style=\"text-align:#{align[idx]}\"" : ''
      html << "<th#{align_attr}>#{parse_inline(cell)}</th>"
    end
    html << "</tr>\n</thead>\n<tbody>\n"
    rows.each do |row|
      html << "<tr>"
      row.each_with_index do |cell, idx|
        align_attr = align[idx] ? " style=\"text-align:#{align[idx]}\"" : ''
        html << "<td#{align_attr}>#{parse_inline(cell)}</td>"
      end
      html << "</tr>\n"
    end
    html << "</tbody>\n</table>\n"
  end

  def render_list(items)
    return '' if items.empty?
    type = items.first[:type]
    html = "<#{type == :ordered ? 'ol' : 'ul'}>\n"
    stack = []
    items.each do |item|
      level = (item[:indent] || 0) / 2
      while stack.length > level
        html << "  " * stack.length + "</#{stack.pop == :ordered ? 'ol' : 'ul'}>\n"
      end
      while stack.length < level
        stack.push(:unordered)
        html << "  " * stack.length + "<ul>\n"
      end
      html << "  " * (level + 1) + "<li>#{parse_inline(item[:content])}</li>\n"
    end
    while stack.any?
      html << "  " * (stack.length + 1) + "</#{stack.pop == :ordered ? 'ol' : 'ul'}>\n"
    end
    html << "</#{type == :ordered ? 'ol' : 'ul'}>\n"
  end

  def parse_inline(text)
    return '' if text.nil?
    text = CGI.escape_html(text.to_s)
    text.gsub!(/`([^`]+)`/, '<code>\1</code>')
    text.gsub!(/\*\*([^*]+)\*\*/, '<strong>\1</strong>')
    text.gsub!(/__([^_]+)__/, '<strong>\1</strong>')
    text.gsub!(/\*([^*]+)\*/, '<em>\1</em>')
    text.gsub!(/_([^_]+)_/, '<em>\1</em>')
    text.gsub!(/\[([^\]]+)\]\(([^)]+)\)/) do
      link_text = $1
      url = $2.sub(/\.md$/, '.html')
      if url.start_with?('#')
        "<a href=\"#{url}\">#{link_text}</a>"
      else
        target = url.start_with?('http') ? ' target="_blank"' : ''
        "<a href=\"#{url}\"#{target}>#{link_text}</a>"
      end
    end
    text.gsub!(/<((https?:\/\/)[^>]+)>/, '<a href="\1" target="_blank">\1</a>')
    text
  end

  def build_page(title, content, filename, prev_file, next_file)
    nav_items = @files.map do |f|
      num = f.match(/^(\d+)/)&.captures&.first
      active = f == filename ? ' class="active"' : ''
      "<a href=\"#{f.sub('.md', '.html')}\"#{active}>#{num}</a>"
    end.join(' ')

    prev_link = prev_file ? "<a href=\"#{prev_file.sub('.md', '.html')}\" class=\"nav-link\">← #{extract_title_from_file(prev_file)}</a>" : ''
    next_link = next_file ? "<a href=\"#{next_file.sub('.md', '.html')}\" class=\"nav-link\">#{extract_title_from_file(next_file)} →</a>" : ''

    <<~HTML
    <!DOCTYPE html>
    <html lang="en" class="dark">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>⚡</text></svg>">
      <title>#{title} – #{@site_title}</title>
      <meta name="description" content="#{@site_description}">
      <style>#{read_css}</style>
    </head>
    <body>
      <div class="container">
        <header>
          <div class="header-row">
            <div class="site-title">#{@site_title}</div>
            <div class="header-links">
              <a href="#{@github_url}" target="_blank" class="icon-link" title="GitHub">
                <svg width="1.2em" height="1.2em" viewBox="0 0 32 32">
                  <path d="M16 2a14 14 0 0 0-4.43 27.28c.7.13 1-.3 1-.67v-2.38c-3.89.84-4.71-1.88-4.71-1.88a3.71 3.71 0 0 0-1.62-2.05c-1.27-.86.1-.85.1-.85a2.94 2.94 0 0 1 2.14 1.45a3 3 0 0 0 4.08 1.16a2.93 2.93 0 0 1 .88-1.87c-3.1-.36-6.37-1.56-6.37-6.92a5.4 5.4 0 0 1 1.44-3.76a5 5 0 0 1 .14-3.7s1.17-.38 3.85 1.43a13.3 13.3 0 0 1 7 0c2.67-1.81 3.84-1.43 3.84-1.43a5 5 0 0 1 .14 3.7a5.4 5.4 0 0 1 1.44 3.76c0 5.38-3.27 6.56-6.39 6.91a3.33 3.33 0 0 1 .95 2.59v3.84c0 .46.25.81 1 .67A14 14 0 0 0 16 2z" fill-rule="evenodd" fill="currentColor"/>
                </svg>
              </a>
            </div>
          </div>
          <p class="top-desc">#{@site_description}</p>
          <nav class="top-nav">
            <a href="index.html">Home</a>
            #{nav_items}
          </nav>
        </header>

        <main>
          <div class="back-link"><a href="index.html" class="link">← Back to Home</a></div>
          <article class="prose">#{content}</article>
          <div class="page-nav">
            <div>#{prev_link}</div>
            <div>#{next_link}</div>
          </div>
        </main>

        <footer>
          <p><a href="https://github.com/z3nnix/cinder">The Cinder programming language</a></p>
        </footer>
      </div>
    </body>
    </html>
    HTML
  end

  def generate_index
    examples = @files.map do |f|
      num = f.match(/^(\d+)/)&.captures&.first
      title = extract_title_from_file(f)
      desc = extract_description(f)
      <<~LI
      <li>
        <a href="#{f.sub('.md', '.html')}" class="example-link">
          <span class="title">#{title}</span>
        </a>
      </li>
      LI
    end.join

    index = <<~HTML
    <!DOCTYPE html>
    <html lang="en" class="dark">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>⚡</text></svg>">
      <title>#{@site_title}</title>
      <meta name="description" content="#{@site_description}">
      <style>#{read_css}</style>
    </head>
    <body>
      <div class="container">
        <header>
          <div class="header-row">
            <div class="site-title">#{@site_title}</div>
            <div class="header-links">
              <a href="#{@github_url}" target="_blank" class="icon-link" title="GitHub">
                <svg width="1.2em" height="1.2em" viewBox="0 0 32 32">
                  <path d="M16 2a14 14 0 0 0-4.43 27.28c.7.13 1-.3 1-.67v-2.38c-3.89.84-4.71-1.88-4.71-1.88a3.71 3.71 0 0 0-1.62-2.05c-1.27-.86.1-.85.1-.85a2.94 2.94 0 0 1 2.14 1.45a3 3 0 0 0 4.08 1.16a2.93 2.93 0 0 1 .88-1.87c-3.1-.36-6.37-1.56-6.37-6.92a5.4 5.4 0 0 1 1.44-3.76a5 5 0 0 1 .14-3.7s1.17-.38 3.85 1.43a13.3 13.3 0 0 1 7 0c2.67-1.81 3.84-1.43 3.84-1.43a5 5 0 0 1 .14 3.7a5.4 5.4 0 0 1 1.44 3.76c0 5.38-3.27 6.56-6.39 6.91a3.33 3.33 0 0 1 .95 2.59v3.84c0 .46.25.81 1 .67A14 14 0 0 0 16 2z" fill-rule="evenodd" fill="currentColor"/>
                </svg>
              </a>
            </div>
          </div>
          <p class="top-desc">#{@site_description}</p>
        </header>

        <main>
          <ul class="examples-list">#{examples}</ul>
        </main>

        <footer>
          <p><a href="https://github.com/z3nnix/cinder">The Cinder programming language</a></p>
        </footer>
      </div>
    </body>
    </html>
    HTML

    File.write(File.join(@output_dir, 'index.html'), index, encoding: 'UTF-8')
  end

  def extract_title_from_file(filename)
    path = File.join(@docs_dir, filename)
    return filename unless File.exist?(path)
    content = File.read(path, encoding: 'UTF-8')
    content =~ /^#\s+(.+)$/ ? $1.strip : filename.sub(/^\d+_/, '').sub('.md', '').gsub('_', ' ').capitalize
  end

  def extract_description(filename)
    path = File.join(@docs_dir, filename)
    return '' unless File.exist?(path)
    lines = File.read(path, encoding: 'UTF-8').lines
    found = false
    lines.each do |line|
      found = true if line =~ /^#/
      next unless found
      if line.strip !~ /^```/ && line.strip !~ /^---/ && line.strip.length > 10
        txt = line.strip
        return txt[0..100] + (txt.length > 100 ? '…' : '')
      end
    end
    ''
  end

  def create_css
    File.write(File.join(@output_dir, 'style.css'), read_css, encoding: 'UTF-8')
  end

  def read_css
    <<~CSS
    * { margin:0; padding:0; box-sizing:border-box; }
    html.dark { background:#000; color:#ccc; }
    body {
      background:#000;
      color:#ccc;
      font-family: -apple-system, monospace;
      line-height:1.6;
      padding:30px;
      min-height:100vh;
      zoom: 0.9;
      -moz-transform: scale(0.9);
      -moz-transform-origin: top center;
    }
    .container {
      max-width:900px;
      margin:0 auto;
      background:#000;
      padding:20px 0;
    }
    a { color:#fff; text-decoration:none; transition:color 0.2s ease; }
    a:hover { color:#aaa; }
    header {
      border-bottom:1px solid #222;
      padding-bottom:15px;
      margin-bottom:30px;
    }
    .header-row {
      display:flex;
      justify-content:space-between;
      align-items:center;
      margin-bottom:10px;
    }
    .site-title { font-size:1.6em; font-weight:400; color:#fff; }
    .header-links { display:flex; gap:12px; align-items:center; }
    .icon-link { color:#fff; transition:color 0.2s; }
    .icon-link:hover { color:#aaa; }
    
    .top-desc { 
      font-style: italic;
      font-size: 1.05em;
      color: #999;
      margin: 5px 0 15px 0;
    }
    
    .top-nav {
      display:flex;
      flex-wrap:wrap;
      gap:15px;
      margin-top:10px;
    }
    .top-nav a {
      display:inline-block;
      color:#fff;
      text-decoration:none;
      font-size:0.95em;
    }
    .top-nav a:hover { color:#aaa; }
    .top-nav a.active { color:#aaa; }

    .back-link { margin-bottom:20px; }
    .link { color:#fff; }
    .link:hover { color:#aaa; }

    .prose { color:#eee; line-height:1.7; }
    .prose h1, .prose h2, .prose h3, .prose h4 {
      color:#fff;
      margin:1.5em 0 0.5em 0;
      font-weight:400;
    }
    .prose h1 { font-size:1.8em; border-bottom:1px solid #222; padding-bottom:0.3em; }
    .prose h2 { font-size:1.5em; border-bottom:1px solid #222; padding-bottom:0.2em; }
    .prose h3 { font-size:1.2em; }
    .prose h4 { font-size:1.0em; }
    .prose p { margin:1em 0; color: #ddd;}
    .prose ul, .prose ol { margin:1em 0; padding-left:2em; }
    .prose li { margin:0.4em 0; }
    .prose blockquote {
      border-left:2px solid #555;
      padding:0.5em 1.5em;
      margin:1em 0;
      background:#050505;
      color:#aaa;
      border-radius:0;
    }
    .prose blockquote p { color:#aaa; }
    .prose hr { border:none; border-top:1px solid #222; margin:2em 0; }
    
    .prose code {
      background:#080808;
      padding:2px 8px;
      border-radius:2px;
      font-family:monospace;
      font-size: 1.25rem;
      color:#e0e0e0;
      border:1px solid #222;
    }
    .prose pre {
      background:#050505;
      padding:20px;
      border-radius:6px;
      overflow-x:auto;
      margin:1.5em 0;
      border:1px solid #222;
      font-family:monospace;
      font-size: 1.25rem;
      line-height:1.5;
    }
    .prose pre code {
      background:none;
      padding:0;
      border:none;
      color:#ddd;
      font-size: 1em;
    }
    .prose table {
      width:100%;
      border-collapse:collapse;
      margin:1.5em 0;
      border:1px solid #222;
    }
    .prose th, .prose td {
      padding:8px 12px;
      border:1px solid #222;
      text-align:left;
    }
    .prose th {
      background:#080808;
      color:#fff;
      font-weight:400;
    }
    .prose td { color:#ddd; }

    .page-nav {
      display:flex;
      justify-content:space-between;
      margin:2.5em 0 1em;
      padding-top:1.5em;
      border-top:1px solid #222;
    }
    .page-nav .nav-link {
      color:#fff;
    }
    .page-nav .nav-link:hover {
      color:#aaa;
    }

    .description {
      color:#aaa;
      font-style:italic;
      font-size:1.05em;
      padding:16px 0;
      border-bottom:1px solid #222;
      margin-bottom:20px;
    }
    .examples-list {
      list-style:none;
      padding:0;
    }
    .examples-list li {
      margin: 12px 0;
      padding: 5px 0;
    }
    .example-link {
      display:inline-block;
      color:#fff;
      text-decoration:none;
      font-size: 1.2em;
    }
    .example-link:hover { color:#aaa; }
    .example-link .title {  }
    .example-link .desc {
      color:#666;
      font-size:0.9em;
      margin-left:10px;
    }

    footer {
      margin-top:40px;
      padding-top:20px;
      border-top:1px solid #222;
      text-align:center;
      color:#444;
      font-size:0.85em;
    }
    footer code { background:#080808; padding:2px 6px; border-radius:3px; color:#666; border:1px solid #222; }

    @media (max-width: 768px) {
      .container { padding:0 15px; }
      .site-title { font-size:1.4em; }
      .page-nav { flex-direction:column; gap:8px; align-items:stretch; }
      .page-nav .nav-link { text-align:center; }
      .top-nav a { font-size:0.9em; }
      .prose h1 { font-size:1.6em; }
      .prose h2 { font-size:1.3em; }
      body { padding:20px; }
    }
    .hljs-comment { color:#666; font-style:italic; }
    .hljs-keyword { color:#f78; }
    .hljs-string { color:#8cf; }
    .hljs-number { color:#8cf; }
    .hljs-function { color:#b8f; }
    .hljs-variable { color:#fa7; }
    .hljs-built_in { color:#fa7; }
    .hljs-class { color:#fa7; }
    .hljs-operator { color:#f78; }
    .hljs-punctuation { color:#ddd; }
    .hljs-title { color:#b8f; }
    .hljs-params { color:#ddd; }
    .hljs-type { color:#9f6; }
    .hljs-meta { color:#fa7; }
    .hljs-symbol { color:#b8f; }
    CSS
  end
end

if __FILE__ == $0
  docs_dir = ARGV[0] || 'docs'
  output_dir = ARGV[1] || 'docs_html'
  MDParser.new(docs_dir, output_dir).parse_all
end
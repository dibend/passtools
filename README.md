<h1>passtools 🛠️</h1>

<p>A minimal set of Bash tools for password generation and password-store (GPG) bootstrapping — with zero fluff and maximum clarity.</p>

<p style="text-align: center;">
  <img src="https://media.giphy.com/media/TqiwHbFBaZ4ti/giphy.gif" alt="Hackerman" width="300" />
</p>

<h2>🔧 Scripts</h2>

<h3><code>pass.sh</code></h3>
<ul>
  <li>Generates a secure 24-character password from <code>/dev/urandom</code>.</li>
  <li>Output contains only printable characters (from <code>[:graph:]</code>).</li>
</ul>

<pre><code>$ ./pass.sh
a$ke9B!LmN1z@vD3Y^qL*r6#</code></pre>

<h3><code>passman.sh</code></h3>
<ul>
  <li>Bootstraps and configures a GPG-backed <code>pass</code> store.</li>
  <li>Detects or helps generate a GPG key.</li>
  <li>Initializes <code>pass</code> with the selected key.</li>
  <li>Optionally initializes Git inside the password store for version control.</li>
  <li>Checks for clipboard utilities like <code>xclip</code>, <code>wl-copy</code>, <code>pbcopy</code>.</li>
</ul>

<h2>📦 Requirements</h2>
<ul>
  <li><code>gpg</code></li>
  <li><code>pass</code> (https://www.passwordstore.org)</li>
  <li><code>git</code> (optional, for versioned store)</li>
</ul>

<h2>🚀 Setup Guide</h2>
<pre><code>$ ./passman.sh</code></pre>
<p>Prompts will guide you through key selection, password store setup, and optional Git integration.</p>

<h2>💡 Example Usage with <code>pass</code></h2>
<ul>
  <li><code>pass insert websites/example.com</code> — Store a new password.</li>
  <li><code>pass generate services/netflix 20</code> — Auto-generate and store a 20-character password.</li>
  <li><code>pass -c wifi/home</code> — Copy password to clipboard.</li>
</ul>

<h2>🔒 Security Notes</h2>
<ul>
  <li>Your GPG key is the master lock — <strong>backup your private key</strong>.</li>
  <li>All stored passwords are encrypted at rest.</li>
  <li>Clipboard integration is supported if tools are installed.</li>
</ul>

<p style="text-align: center;">
  <img src="https://media.giphy.com/media/xT9IgG50Fb7Mi0prBC/giphy.gif" alt="Security" width="300" />
</p>

<p>use at your own risk.</p>

<h2>🙌 Credits</h2>
<p>Built with 💛 by <a href="https://github.com/dibend">dibend</a></p>

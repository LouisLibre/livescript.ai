// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

// ls is namespace for livescript
var ls_fileInput = undefined;
var ls_onFileChange = function (e) {
  console.log("File changed:", e.target.files?.[0]);
  const file = e.target.files?.[0];
  if (!file) return;
  const url = URL.createObjectURL(file);
  ls_loadVideo(url);
};

var ls_loadVideo = function (url) {
  console.log("Loading video:", url);
  const video_el = document.createElement("video");
  video_el.src = url;
  video_el.controls = true;
  video_el.className = "w-full";
  video_el.setAttribute("playsinline", "true");
  video_el.setAttribute("webkit-playsinline", "true");

  const left_sidebar = document.getElementById("left_sidebar");
  left_sidebar.innerHTML = "";
  left_sidebar.appendChild(video_el);
};

let Hooks = {};
Hooks.UploadParentDiv = {
  mounted() {
    // This.el is the parent <div>
    ls_fileInput = this.el.querySelector('input[type="file"]');
    console.log("ls_fileInput:", ls_fileInput);
    if (!ls_fileInput) return;

    ls_fileInput.addEventListener("change", ls_onFileChange);
  },
  destroyed() {
    if (ls_fileInput) {
      console.log("Destroying ls_fileinput event listener");
      ls_fileInput.removeEventListener("change", ls_onFileChange);
    }
  },
};
Hooks.SeekOnClick = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      // Retrieve the start time from the data attribute
      const startTime = parseFloat(this.el.getAttribute("data-start-time"));

      // Locate the video element that was loaded in #left_sidebar
      const video = document.querySelector("#left_sidebar video");

      if (video) {
        video.currentTime = startTime;
        video.play(); // optional, automatically play
      }
    });
  },
};

window.addEventListener("phx:play-video", () => {
  const video = document.querySelector("#left_sidebar video");
  if (video) {
    video.play().catch((err) => {
      console.warn(
        "Video playback blocked by browser. User interaction may be required.",
        err
      );
    });
  }
});

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// Custom JS
document.addEventListener("DOMContentLoaded", () => {
  document.querySelector("input[name=file]").addEventListener("click", () => {
    // Send a message to the server
    console.log("hello");
  });
});

class SkeletonLoader extends HTMLElement {
  static get observedAttributes() {
    return ["count", "width", "height", "circle", "translucent"];
  }

  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this.baseStyles = `
      :host {
        --color: #eee;
        --highlight: #f5f5f5;
        --animation-duration: 1.5s;
        display: block;
      }
      
      .skeleton-item {
        background: linear-gradient(
          90deg,
          var(--color) 25%,
          var(--highlight) 37%,
          var(--color) 63%
        );
        background-size: 400% 100%;
        animation: skeleton-loading var(--animation-duration) ease infinite;
        margin-bottom: 0.5rem;
        border-radius: 4px;
      }

      @keyframes skeleton-loading {
        0% { background-position: 100% 50% }
        100% { background-position: 0% 50% }
      }
    `;
  }

  connectedCallback() {
    this.render();
  }

  attributeChangedCallback() {
    this.render();
  }

  getLineStyles() {
    return `
      width: ${this.width || "100%"};
      height: ${this.height || "1rem"};
      ${this.circle === "true" ? "border-radius: 50%;" : ""}
    `;
  }

  render() {
    const count = parseInt(this.getAttribute("count")) || 1;
    this.width = this.getAttribute("width") || "";
    this.height = this.getAttribute("height") || "";
    this.circle = this.getAttribute("circle") || "false";
    this.translucent = this.hasAttribute("translucent");

    const styles = `
      ${this.baseStyles}
      :host {
        --color: ${this.translucent ? "rgba(0,0,0,0.06)" : "#eee"};
        --highlight: ${this.translucent ? "rgba(0,0,0,0.09)" : "#f5f5f5"};
      }
    `;

    this.shadowRoot.innerHTML = `
      <style>${styles}</style>
      ${Array.from(
        { length: count },
        (_, i) => `
        <div class="skeleton-item" 
          style="${this.getLineStyles()} 
          ${i === 0 && this.circle === "true" ? "border-radius: 50%;" : ""}">
        </div>
      `
      ).join("")}
    `;
  }
}

customElements.define("skeleton-loader", SkeletonLoader);

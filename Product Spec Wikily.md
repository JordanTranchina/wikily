# **Product Specification: Wikily (MVP)**

**Status:** Draft | **Target Release:** Q3 2026 | **Author:** Product Management

**Technical Strategy:** Fork of Pluely Core (Leveraging Pluely's macOS HUD & Audio Hooking)

## **1\. Product Overview & Vision**

### **1.1 Elevator Pitch**

**Wikily** is a zero-latency, proactive macOS overlay that assists customer-facing teams during live Zoom calls. Forked from the open/internal **Pluely** codebase, Wikily inherits Pluely's robust macOS desktop wrapper and audio-routing pipeline, but strips out its cloud-heavy post-call analyses.

Instead, Wikily redirects those streams to a local, offline matching engine that queries a pre-compiled, highly-interlinked markdown wiki (inspired by Andrej Karpathy’s "LLM Wiki" design pattern). It pushes real-time, context-aware answers and documentation links directly to the user's screen.

### **1.2 The Problem**

Customer support and success representatives have virtually no prep time between client calls. When a client asks a highly technical or custom account-related question, the rep must manually search internal knowledge bases (Notion, Google Docs, PDFs) on the fly. This results in:

* Long, awkward pauses during client interactions.  
* Inaccurate or "I'll have to get back to you on that" responses.  
* High cognitive overload and conversational anxiety for the rep.

### **1.3 The Solution (The Pluely Fork Strategy)**

Rather than building a macOS audio routing driver and custom UI panel from scratch, Wikily is built as a **direct fork of Pluely**.

Pluely excels at desktop integration (HUD display, manual search triggers, global shortcuts) but suffers from high latency due to cloud-heavy RAG retrieval. By forking Pluely, we:

1. **Reuse:** Keep the robust Swift/SwiftUI frontend overlay and system-level audio capture logic (ScreenCaptureKit / CoreAudio).  
2. **Pivot:** Replace Pluely's remote cloud backend with a local, zero-latency vector comparison matching engine and a pre-compiled markdown wiki directory on the user's machine.

### **1.4 Core Hypothesis**

Customer Service Representatives (CSRs) will experience a significant drop in call anxiety, shorter handle times, and a higher rate of first-contact resolution if an assistant proactively feeds them highly relevant, structured context (sourced from Notion or a local wiki/folder) based dynamically on live, speech-to-intent analysis of the ongoing conversation.

### **1.5 Competitive & Foundation Matrix**

* **Cluely:** Rely on cloud-heavy post-call analyses or clunky, manual, search-first sidebar panels.  
* **Pluely (Upstream Foundation):** Stable macOS utility that provides manual hotkey search overlays and cloud-based call recording transcription.  
* **Wikily (Our Fork):** Real-time, local-first proactive overlay that maps speech-to-intent and surfaces pre-linked, stateful wiki structures entirely offline.

## **2\. Target User & Core Workflow**

### **2.1 Persona: The Customer Support Specialist (CSR)**

* **Context:** Conducts 8–10 Zoom troubleshooting and onboarding calls daily.  
* **Current Behavior:** Keeps Obsidian, Notion, and a browser with 20 tabs open. Searches frantically whenever a specialized issue is brought up.  
* **Desired Behavior:** Speaks naturally with the customer, keeps eyes on the camera, and relies on peripheral glances at a clean UI HUD to get answers.

### **2.2 Ideal MVP Workflow**

1. **Preparation:** The rep boots up Wikily (onboarded via Pluely’s existing login/local configuration flow) and points it to their local "LLM Wiki" directory (e.g., an Obsidian vault compiled using the Karpathy pattern).  
2. **Initiation:** The rep joins a Zoom meeting. Wikily detects the audio stream using Pluely's upstream audio listener.  
3. **Active Monitoring:** A client says: *"We are having trouble setting up the OAuth redirect URI for our Sandbox environment."*  
4. **Proactive Trigger:** Wikily’s fork-optimized transcription engine captures the utterance, extracts key entities (OAuth redirect URI, Sandbox), and runs a local semantic match.  
5. **HUD Delivery:** Within 1.5 seconds, Pluely's inherited HUD window fades onto the rep's screen containing a 2-sentence configuration summary, the exact sandbox URL to copy, and a direct link to open the deep wiki page.

### **2.3 Concrete Use Case: The "Becky Promotion" Query**

To validate the core hypothesis, the system must handle highly dynamic, project-specific questions that customer support reps would normally struggle to answer without clicking through several Notion projects.

* **The Scenario:** A client is checking in on an active task or marketing campaign.  
* **The Utterance:** *"How are you progressing with the Becky promotion?"*  
* **Behind the Scenes:**  
  * Wikily's streaming transcription records: "...progressing with the Becky promotion?"  
  * The matching engine extracts the entity Becky promotion and runs a local vector comparison.  
  * It identifies a mapped node in the local directory (or a cached Notion page sync) titled Project: Becky Promotion Campaign.  
* **The HUD Display (Inherited Pluely HUD Styling):**  
  The overlay displays a card summarizing the current status of the task or project:  
  * **Title:** Task: Becky Promotion  
  * **Status:** In Progress (Deployment phase)  
  * **Latest Update:** "Visual assets approved by design team yesterday. Launch scheduled for next Tuesday."  
  * **Key Blocker:** None (Previously waiting on design asset approval, resolved).  
  * **Quick Links:** \[Open Notion Task ↗\] | \[View Assets ↗\]

## **3\. MVP Scope & Features**

\+-------------------------------------------------------+  
|  \[Zoom Active Window\]                                 |  
|                                                       |  
|                                                       |  
|                                                       |  
|     \+-------------------------------------------+     |  
|     | Wikily HUD (Floating Overlay \- Pluely Fork)|     |  
|     |                                           |     |  
|     |  💡 Topic: Becky Promotion Campaign        |     |  
|     |  \---------------------------------------  |     |  
|     |  Status: In Progress | Launch: Next Tue   |     |  
|     |  Assets approved. No blockers.            |     |  
|     |                                           |     |  
|     |  \[Copy Status\] \[Open Notion Task ↗\]       |     |  
|     \+-------------------------------------------+     |  
\+-------------------------------------------------------+

### **3.1 Live Audio Capture & Local Transcription (Pluely-Enhanced)**

* **Inherited System Audio Routing:** Use Pluely’s existing virtual loopback driver/ScreenCaptureKit audio pipeline to tap outgoing mic audio and incoming Zoom client audio cleanly.  
* **On-Device/Low-Latency Transcription:** Replace Pluely's cloud-transcription endpoints with a lightweight, local transcription model (e.g., Whisper.cpp running on Apple Silicon Neural Engine) to keep processing entirely on-device.  
* **Sliding Window Context:** Keep a moving window of the last 15–30 seconds of conversation transcript to extract semantic intent.

### **3.2 The Karpathy-Inspired Local Wiki Engine**

The core database is a structured local directory of .md files. Rather than traditional RAG over raw documents, the database is assumed to be compiled beforehand using an LLM pipeline into an interlinked knowledge graph (with clear summaries, index tables, and cross-references).

* **Directory Mapping:** User selects a local directory path (e.g., \~/Documents/MyKnowledgeWiki) using a setting pane built on top of Pluely’s settings UI.  
* **Semantic Search Indexing:**  
  * Build a local vector index of the markdown summaries.  
  * Perform real-time matching using Cosine Similarity:![][image1]  
    where ![][image2] is the embedding vector of the active transcript window, and ![][image3] represents the document/header embedding of pages in the local wiki directory.  
* **Entity & Concept Extraction:** Extract entities (e.g., product names, project names like "Becky promotion", error codes) and map them to existing file names or \#tags in the markdown vault.

### **3.3 Proactive macOS HUD / Overlay (Pluely Fork UI)**

* **Unobtrusive UI Design:** Repurpose Pluely's custom NSPanel overlay (which supports remaining on top of full-screen Zoom windows, custom opacity, dragging, and resizing).  
* **Frictionless Actions:**  
  * **Proactive Cards:** Instead of Pluely's manual search trigger, implement a background observer that auto-fades in cards when local match confidence exceeds a defined threshold (e.g., ![][image4]).  
  * **Copy-to-Clipboard:** Quick buttons to copy status updates or links.  
  * **Deep Linking:** Clicking a card's title opens the matching Markdown file locally or remote browser link (e.g., Notion) directly.

## **4\. Technical Architecture (MVP)**

\+------------------------------------------------------------------------+  
|                            Pluely Core (Upstream)                      |  
|  \- Zoom Audio Capture (ScreenCaptureKit)   \- SwiftUI HUD Window Panel  |  
\+------------------------------------------------------------------------+  
                               |  
                        Audio Streams & UI Hook  
                               v  
\+------------------+     Audio Stream     \+----------------------+  
| Zoom Call Audio  | \-------------------\> | Whisper (Local/API)  |  
\+------------------+                      \+----------------------+  
                                                     |  
                                                     | Live Transcript  
                                                     v  
\+------------------+   Semantic Match     \+----------------------+  
| Local MD Wiki    | \<------------------- |  Context Processor   |  
| (Compounded DB)  |                      \+----------------------+  
| (Wikily Custom)  |                      | (Wikily Match Logic) |  
\+------------------+                      \+----------------------+  
                                                     |  
                                                     | Proactive Trigger  
                                                     v  
                                          \+----------------------+  
                                          |   macOS HUD Overlay  |  
                                          |  (Pluely NSPanel UI) |  
                                          \+----------------------+

### **4.1 System Requirements & Tech Stack**

* **Platform:** macOS 14.0+ (Optimized for Apple Silicon CoreML/Neural Engine).  
* **Frontend/App Framework:** Swift / SwiftUI (Forked from Pluely, ensuring instant compatibility with floating panels over active Zoom calls).  
* **Backend / Processing Core:** Swift-native local database integration \+ bundled Python helper binary or Rust-based core for local embeddings and markdown parsing.

### **4.2 Data & Security Architecture**

* **100% Local-First:** In compliance with strict enterprise customer privacy policies, client call audio and transcripts **must never** be stored on Wikily's or Pluely's remote servers. All cloud sync mechanisms present in original Pluely are programmatically bypassed or disabled.  
* **LLM Choice:** Allow the user to configure a local LLM (e.g., Llama-3 via Ollama) or map to an OpenAI/Anthropic API key for generating final contextual summaries.

## **5\. Progressive Implementation Sequence (Compounding Milestones)**

Because we are starting with the Pluely codebase, we do not need to build audio capture pipelines or window renderers from scratch. The milestones focus on *verifying and redirecting* Pluely’s components, then introducing the local wiki-matching engine.

\[M1: Audio Routing Test\] \---\> \[M2: Dual-Stream Transcription\] \---\> \[M3: Wiki Parsing Integration\]  
                                                                                |  
                                                                                v  
\[M5: Full Loop Proactive Trigger\] \<---------------------------- \[M4: Local Semantic Retrieval Match\]

### **5.1 Milestone 1: Fork Pluely & Validate Bidirectional Audio Loopback**

* **Goal:** Confirm the compiled Pluely fork runs natively and can capture both client audio (system loopback) and the user's microphone stream simultaneously.  
* **Verification Criteria:**  
  * Compile the forked project.  
  * Trigger the upstream audio engine and successfully verify that both the user's mic and incoming Zoom audio feed into local memory buffers with zero latency or feedback loops.

### **5.2 Milestone 2: Integrate Low-Latency Transcription Pipeline**

* **Goal:** Feed Pluely’s active audio buffers into a fast, local streaming transcription system.  
* **Verification Criteria:**  
  * Route the real-time audio streams into local Whisper.cpp or a highly-optimized streaming API.  
  * Print a continuous, speaker-tagged transcript (\[Client\], \[User\]) to the developer console within ![][image5] of spoken utterances.

### **5.3 Milestone 3: Integrate Local Wiki Reader**

* **Goal:** Implement the local filesystem directory reader on top of the forked settings panel.  
* **Verification Criteria:**  
  * Add a directory picker to Pluely’s configuration screen.  
  * Recursively scan, parse (YAML frontmatter, headers, markdown tags), and index a local Obsidian/Karpathy-style directory of 100+ files in under ![][image6].

### **5.4 Milestone 4: Match Live Transcripts to Relevant Local Files**

* **Goal:** Apply the local Cosine Similarity engine to compare the sliding live transcript window against the local wiki index.  
* **Verification Criteria:**  
  * With a mock conversational transcript running ("Where are we on the Becky promotion?"), query the local vector index.  
  * Successfully resolve and retrieve the file Project: Becky Promotion Campaign with a matching similarity score of ![][image7] completely offline.

### **5.5 Milestone 5: Wire Up the Proactive HUD (The Full Loop MVP)**

* **Goal:** Connect the semantic matching engine to Pluely’s HUD panel interface, making card displays proactive rather than manual.  
* **Verification Criteria:**  
  * Speak the target query into the microphone while simulated client audio is playing.  
  * Within 1.5 seconds, the HUD overlay automatically transitions from transparent, fades in, and renders the "Becky Promotion" status card complete with Notion backlinks and key metrics.

## **6\. Future Roadmap (Post-MVP)**

* **Notion Cloud Sync Engine:** Connect to Notion via OAuth, download workspace databases, and dynamically compile them into the local Markdown schema structure locally to keep the Karpathy wiki continuously updated.

## **7\. Key Metrics for Success (KPIs)**

1. **Development Velocity Boost:** Using the Pluely fork should cut initial MVP development time from 6 months to **under 8 weeks** by reusing the audio driver and window-level UI panels.  
2. **Information Relevance (Accuracy):** Implicit user engagement (clicking the "Copy" button, opening Notion deep links, or expanding details) should be ![][image8].

[image1]: <data:image/png;base64,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>

[image2]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABIAAAAZCAYAAAA8CX6UAAABA0lEQVR4XmNgGAUUAUVFRTdlZWVZdHGSgby8/H8QRhcnCQANaIIZBMRB6PJEAyRDQPgfujxRQFZWVhnNoP9aWlps6OoIAqDGl0B8HYiLkQzbj66OIABplJaWFoaxYRhdHV4A1NCFrAnIvgozSEFBIRJZLV4A1VQC4yspKfGT7CoZGRkVqIavUPwdiP8gG6SiosKOrg8DyEMC+S4QJyFjOTm56UiGEQ50qI2i6OIggGQQdu8BbdMCBmIEEK8CKQIFKJA2hMmrq6vzguSBYh+RDOsGiQHTmxTcIKBgjTzES4+B+AmIDVQ0ASYPZGsAxd4D8TOoGhB+CsRvgY7wgRs0CkYyAAAkEmZQuC0zwwAAAABJRU5ErkJggg==>

[image3]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABEAAAAZCAYAAADXPsWXAAAA4ElEQVR4XmNgGAW0AXJycm3y8vL/icFAtRvQ9aMABQWFQphiaWlpYWQ5cXFxbiTDfiDLoQB8hoAAUPwnTF5ZWVkMXR4MiDDkCkxeSUlJDV0eDIgwBCwHxH/R5eAA2RAgrgbyC4ABWQ7E/Ujia9H1oQBkQ6AxVgOk64B0ExDvhcp9B6pTQNcLB4S8AzQwHyYPVKuBLg8GhAwBAZg8CKPLgQFdDAGKRyEZchNFUlFRUQ9oQDhQYhGSohSoGEhjMhBvRZL7h2IACODJO3+A+BcQfwfiT0B1B4EGu6PrHwUjAgAATbaC9rTpf1cAAAAASUVORK5CYII=>

[image4]: <data:image/png;base64,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>

[image5]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACIAAAAZCAYAAABU+vysAAABjElEQVR4Xu1UPUsDURCMitiLoBzHXe64xvp+geAPEMTOVvADRSWFYGEQCwsra1uxsFEECwv/Q0DBRlIYxK8irSnUWdwnm82e+ILlDQzJzs7um7vcpVIpUcITcRzXqtXqktZ/A2amwDvwEzzW/T8DwydghxcRl7WnCPBugh+uxkUs0g7p6Qt9BCH/pNYQaF9q3vAJgsNmrKuH9m7pXvAJAt+1dSC0ptIHUR+BD+AeWBM9G55B2gVBboU+pDy6tsFBVrRugb09S6E1nE67tAc/6bmsTdBQFEWrWrcA76M+hPUbp4dhOOoCg4dpmkbab4KDrGndQlz8jNxLHfvmRRhiW/pNkBG3bl3rFuDdLgjy89ZkWTaiert8Rl3qPWDThtYJuLK5JEnGpUZ+uv1aAy/oO2Z2sG9L9RvQrqTWhSAIxnjJge4BA9zrugOon8Cmq3HABHnyPB/mum7NIOC01FzjFHwFW/H3u06fz2BH+jB8Fhv/AdDe2H9Jh8KXuh4HmQVfqMf9BTlfokSJEv+BLyyVkPl6NcqPAAAAAElFTkSuQmCC>

[image6]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADgAAAAZCAYAAABkdu2NAAACq0lEQVR4Xu2WO2hUQRSGN4koKoiKcWFd9i53t1obwSJFBBvBykIFKzsRfCEIClr4QO0sxGehEQvRQizUUq0EQa2MhFgKRvGBkfgWFeP/e8/o2X9nN1arxf3hsHO++WfOzL1zJykUcuXK9V+oUqksS5LkNWIScReoVz0U+vYi3iE+ITZoP1Uul+uY757NdUv7uy4s4gTitMu5+EksMhXfKOKmy0cQd7ynWq0u51iXL/H5PxEXgIUMKPMLq9frc2ILtbFzJd8snq9Jdiq6r2KxOFs3QylD+4F6jNM3xHatVlvInL/egw3fiI3tmlD8EI7joDDdYFMe45hjX8wDfj7wUqm0gG8Y7Gh40/hdif6LYIvDGOSrwS+DbQ/MqRf9Q4gxxGHETjVMKVv4D8lbFu85FnO1jeeU86Ron7VxZ5A/IefGje1CfOPJKmQbIZtw0/VJDc2nFp7cQw5C0VmBWaGWiTzHuNsxD/gxctyuiwKLzYf8LVmj0ZgeGMbu8T60t+o4eK75vKNgHuAEuFT6PY8tSDl+L7XxnDQ+zTGOe+xsZC91PNazwzM8pPmhJuJ4mqYV7+8oHJd5HIjNzdC+MGkn3u4bBDun3MaNCnsa8W1ThjrrQ10Lf4Tb6td59wD5Bdd+r/3GWeAR27yomP/NLcqcn4IwXhrq2+KZPnz0HbS5DnjeosRdKDGGxa/T4hQZ+pb6HLFGPB8Qb4TRNyIs9gabvjnU2o/N7BbPMB+iZ01Ksj/ELNgS4uOT2uTyI+qxt/XdoR4bV3UsbHBM2ITOl9gbQrOPOd9UxPMCG1/h2W/xZrNisfgs3pnkKHIfv8OIL8A93kNZ30fEFfp9cbRXJdllwuPINzZuY8YtJ39Vyf435mfxzNhz1L1uG1xLD+dmwLvxT/VcuXLlypUrV9BP/8gvSrWZvewAAAAASUVORK5CYII=>

[image7]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADoAAAAZCAYAAABggz2wAAACdUlEQVR4Xu2Wv48NURTHn2gIERHPS96vec97IoRmFYhQEA2JbTbYRgiF+BGFWqLYaLaSqNAo+BuITqKhIZFViN1KtclahPgRy+fEnZfjvHvGzIpCdj7JN7v3e849d86982amUikpKVmyJElyBb1Hn9BpG4/R6XSukzvTbrcvoROMx9FxdEykc6UmWkA/0C0di0LBgyH5nI0tFmpNoYdq/AI91jkxyJkO1xKVyptAF9T4kI5nQsN7QsFJGytCv99fE1tUPE5lrfU1Yf39rVZrW7PZ3MQ1bRThfWXuCp2n5wVvVu4A67vIAkz6gu7ZWB6Y98y5EGnitvU1xBci3mSibn3ZrFB/mUqTvDliJ7WXi3q9vp7Jb5n8yMayCA15jQ75WbDp65jz2vppLU77gIxrtdqqorWHkFuGIjNoiuFyG7d4DXl+Fl4+/uW0Hnrj5RWm1+ttoNg8O3jfxixeQ57vwQafIn/a+inE7qpm5XTHbE5uut3u5uTXg+COjXl4DXm+h+R6vzlir5Lw0KTBB2lteYjZ3ExocF/YpWs29ie8hjw/Br/NvuRWq9XVNoZ/Bs1rr9FoNIvUl9tlPExY9DuVuR9iC4a6L60fg7ybsRpCqDP0AcJp7vXmDODkLkoSyUdsrCjUOhpbUDxiO9JxeMid1zkpSfjisb6A/w7dsH56F1h/AAteJWHE+n+DLEjds2os78LfLkLGofmt2tcx6wscRi/UH3xACHgfJaa9fw67uzJczBP+PkefK+YFT2wU/6n2UvC/e40KxHaHzfgmDcr/rLnd5i1N2IkGO3I4jziFXXb+f4N86tHAzjyi2S12fklJSUlJTn4Chc/eIfM5Q9oAAAAASUVORK5CYII=>

[image8]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADsAAAAZCAYAAACPQVaOAAAC3klEQVR4Xu2WW4hNYRTHZ3IeRFLI0bntc8FpKBmlIYVCHhTiAXmbNyRP4klkSJFSiCRR5knx5pJSHuRSSkKePHigyEgoE47fmvN9p9WafTp7nzlhav9rtff6r8u31rfXt/fu6kqQ4J+iUCjMy2azOctrFIvFWZYbdwiC4CMygJxEXli7AL6E1Cz/VyALI4eRfmQ7u74V2SJSqVTy3i+Xy83mqT1y/nd1DgHcZuSX0j8gw+S5j6xFNqIPSTxPfrqODQWLrXGL7bS2dlAulwsuX6iIXfwodIXoPg59odYF6O+RJ0rfW61Wp8h9JpOZxCVF/fPhBxtBUUDQMlfQcWuLA+J3BfWR66Wxufl8vkLuMrKPhs4rvxr6DhM7jDzUPsg9r+O/kjyrvO59tB4LjNYcEvyIvVsOFHPbciBFvu9eYZRnSpFy1U40c0cXz/3NQJ1T7o/gM1HpTyONbyswJjNINiTnw9rigjw/tc6GHAh7IvCXNM/afaZ5O/ZXvd4RyE6S9A3yEnWCtbcCcWfJcUhzNHUjrFm4M5Yn9pRsOvKlVCotUL6j4jsCN3afKfKWtbVCWFEyLU14aazGUcpamwY+z/GZ5nU3EXLee7VfLLCTVUlCEZetLQqIPRHWFNxgE/6041PW5sELbzE+V7zO/Tvq2+/u33LpbjhHAU0ul0XZsaPWFgeSg0IeW77ZmYW7GMZrGHu39Ue/rvWmoLBtEhx06Jvrmj1mef+Za/U2tsD2is/ZVKUvtf7o37Q+Ciy+W4IYkfXW1i4ofIPkJPceaxO4Td1kuK/IJ815uMYuGK4nVrMUdRCHRZYfK2jynGuo39oE7inqT9LISMIXFdcAtt+WE4Q0G22MO4mg/l8rzTbdSGzP5Ekg18SXDVptfQTYXqfT6cmWF2B7ELhjF7TzgvrfQBMDltOQpxnU//qabuwI5JuG07oowoQtsfHjCvJbSBN9UYSGe2x8ggQJEiQYI/4A2LnkmcVFd1AAAAAASUVORK5CYII=>
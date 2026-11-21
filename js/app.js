(() => {
  const cardGrid = document.getElementById("cardGrid");
  const sectionLabel = document.getElementById("sectionLabel");
  const emptyMsg = document.getElementById("emptyMsg");
  const modalOverlay = document.getElementById("modalOverlay");
  const modalBox = document.getElementById("modalBox");
  const mainContent = document.getElementById("mainContent");
  const specialPage = document.getElementById("specialPage");
  const filterBar = document.getElementById("filterBar");
  const viewNews = document.getElementById("view-news");
  const viewBrain = document.getElementById("view-brain");
  const viewConnect = document.getElementById("view-connect");
  const tabNews = document.getElementById("tab-news");
  const tabBrain = document.getElementById("tab-brain");
  const tabConnect = document.getElementById("tab-connect");

  let allPosts = [];
  let currentTab = "all";
  let currentCat = "ALL";
  let currentAgency = "";
  let currentDays = "3";
  let currentSearch = "";
  let latestDate = new Date();
  let bootstrapped = false;

  function parseHash() {
    const raw = (location.hash || "").replace(/^#\/?/, "").trim();
    if (!raw || raw === "news" || raw.startsWith("r/")) return { main: "news" };
    if (raw === "brain" || raw.startsWith("brain/")) {
      const nodeId = raw.startsWith("brain/") ? decodeURIComponent(raw.slice(6)) : "";
      return { main: "brain", nodeId };
    }
    if (raw === "connect") return { main: "connect" };
    return { main: "news" };
  }

  function setHash(main, nodeId) {
    if (main === "brain") {
      location.hash = nodeId ? `#/brain/${encodeURIComponent(nodeId)}` : "#/brain";
      return;
    }
    if (main === "connect") {
      location.hash = "#/connect";
      return;
    }
    location.hash = "#/";
  }

  function setMainTab(main) {
    const isNews = main === "news";
    const isBrain = main === "brain";
    const isConnect = main === "connect";
    tabNews?.classList.toggle("is-active", isNews);
    tabBrain?.classList.toggle("is-active", isBrain);
    tabConnect?.classList.toggle("is-active", isConnect);
    if (viewNews) viewNews.hidden = !isNews;
    if (viewBrain) viewBrain.hidden = !isBrain;
    if (viewConnect) viewConnect.hidden = !isConnect;
    document.body.classList.toggle("is-brain", isBrain);
    document.body.classList.toggle("is-connect", isConnect);
  }

  async function handleBrainRoute(parsed) {
    if (window.BrainGraph) {
      await window.BrainGraph.show({ crimeType: "", mode: "all" });
      if (parsed.nodeId) window.BrainGraph.select(parsed.nodeId);
    }
    if (window.GraphRag) {
      window.GraphRag.setPosts?.(allPosts);
      window.GraphRag.setMode?.("all");
    }
  }

  async function refreshConnectPanel() {
    const nc = window.NewsConnect;
    if (!nc) return;
    const saved = nc.load?.() || {};
    const baseInput = document.getElementById("connect-public-base");
    if (baseInput && saved.publicBase != null) baseInput.value = saved.publicBase || "";
    const endpoints = (await nc.resolve?.()) || {};
    const llmEl = document.getElementById("connect-llm-url");
    const mcpEl = document.getElementById("connect-mcp-url");
    if (llmEl) llmEl.textContent = endpoints.llm || "—";
    if (mcpEl) mcpEl.textContent = endpoints.mcp || "—";
  }

  function bindConnect() {
    const status = document.getElementById("connect-status");
    const reply = document.getElementById("connect-llm-reply");
    const baseInput = document.getElementById("connect-public-base");

    document.getElementById("connect-save")?.addEventListener("click", () => {
      const nc = window.NewsConnect;
      if (!nc) return;
      nc.save?.({ publicBase: (baseInput?.value || "").trim() });
      refreshConnectPanel();
      if (status) status.textContent = "บันทึกแล้ว (เฉพาะเบราว์เซอร์นี้)";
    });

    document.getElementById("connect-test")?.addEventListener("click", async () => {
      const nc = window.NewsConnect;
      if (!status || !nc?.testMcp) return;
      status.textContent = "กำลังทดสอบ MCP…";
      try {
        const result = await nc.testMcp();
        if (result?.ok) status.textContent = `MCP ผ่าน · เครื่องมือ: ${(result.names || []).join(", ")}`;
        else status.textContent = result?.message || JSON.stringify(result);
      } catch (err) {
        status.textContent = `MCP ล้มเหลว: ${err.message || err}`;
      }
    });

    document.getElementById("connect-test-llm")?.addEventListener("click", async () => {
      const nc = window.NewsConnect;
      if (!status || !nc?.testLlm) return;
      status.textContent = "กำลังทดสอบ LLM…";
      if (reply) {
        reply.hidden = true;
        reply.textContent = "";
      }
      try {
        const result = await nc.testLlm();
        if (result?.ok) {
          status.textContent = "LLM ตอบแล้ว";
          if (reply) {
            reply.hidden = false;
            reply.textContent = result.text || "";
          }
        } else {
          status.textContent = result?.reason || "LLM ล้มเหลว";
        }
      } catch (err) {
        status.textContent = `LLM ล้มเหลว: ${err.message || err}`;
      }
    });

    baseInput?.addEventListener("change", () => {
      refreshConnectPanel();
    });
  }

  async function route() {
    if (!bootstrapped) return;
    const parsed = parseHash();
    setMainTab(parsed.main);
    if (parsed.main === "brain") {
      await handleBrainRoute(parsed);
      return;
    }
    if (parsed.main === "connect") {
      refreshConnectPanel();
    }
  }

  async function loadAllPosts() {
    try {
      const r = await fetch("./data/manifest.json");
      const f = await r.json();
      const names = Array.isArray(f) ? f : Array.isArray(f.days) ? f.days.map((d) => d.news_file || d.crime_file || d) : [];
      const d = await Promise.all(
        names.map((x) => {
          const file = typeof x === "string" ? x : "";
          if (!file) return Promise.resolve({ posts: [] });
          return fetch(`./data/${file}`).then((res) => res.json()).catch(() => ({ posts: [] }));
        })
      );
      allPosts = d
        .flatMap((day) =>
          (day.posts || []).map((p) => ({
            ...p,
            date: day.date || p.date,
            generated_at: day.generated_at || day.date,
          }))
        )
        .sort((a, b) => {
          const dateA = new Date(a.date);
          const dateB = new Date(b.date);
          if (dateB.getTime() !== dateA.getTime()) return dateB - dateA;
          return new Date(b.published_at || b.date) - new Date(a.published_at || a.date);
        });
      if (allPosts.length > 0) {
        latestDate = new Date(allPosts[0].date);
        latestDate.setHours(23, 59, 59, 999);
      }
      populateAgencies();
      updateStats();
      renderCards();
      window.GraphRag?.setPosts?.(allPosts);
    } catch (e) {
      sectionLabel.textContent = "ไม่สามารถโหลดข้อมูลได้";
      console.error(e);
    }
  }

  function populateAgencies() {
    const a = [...new Set(allPosts.map((p) => p.agency).filter(Boolean))].sort();
    const s = document.getElementById("agencyFilter");
    s.innerHTML = '<option value="">ทุกหน่วยงาน</option>';
    a.forEach((x) => {
      s.innerHTML += `<option value="${x}">${x}</option>`;
    });
  }

  function updateStats(filtered) {
    if (!filtered) filtered = getFiltered();
    const bd = filtered.filter((p) => p.urgency === "high" || p.bd_opportunity).length;
    const ag = new Set(filtered.map((p) => p.agency)).size;
    document.getElementById("statTotal").textContent = `${filtered.length} ข่าว`;
    document.getElementById("statAgencies").textContent = `${ag} หน่วยงาน`;
    document.getElementById("statBD").textContent = `${bd} โอกาส BD`;
  }

  function mapCat(p) {
    const c = (p.topic || "").toUpperCase();
    if (c.includes("การเงิน") || c.includes("เศรษฐกิจ") || c.includes("การลงทุน")) return "ECONOMY";
    if (c.includes("นโยบาย") || c.includes("กฎหมาย")) return "POLICY";
    if (c.includes("การเมือง")) return "POLITICS";
    if (c.includes("พลังงาน")) return "ENERGY";
    if (c.includes("ดิจิทัล") || c.includes("ไซเบอร์") || c.includes("เทคโนโลยี")) return "DIGITAL";
    if (c.includes("สาธารณสุข") || c.includes("สุขภาพ")) return "HEALTH";
    if (c.includes("คมนาคม") || c.includes("อุตสาหกรรม") || c.includes("โครงสร้าง")) return "INFRA";
    if (c.includes("การค้า") || c.includes("ท่องเที่ยว") || c.includes("พาณิชย์")) return "TRADE";
    if (c.includes("ความมั่นคง") || c.includes("กลาโหม") || c.includes("ต่างประเทศ")) return "POLICY";
    if (c.includes("แรงงาน") || c.includes("การจ้างงาน")) return "TRADE";
    return "POLICY";
  }

  function getFiltered() {
    let f = [...allPosts];
    if (currentTab === "bd") f = f.filter((p) => p.urgency === "high" || p.bd_opportunity);
    else if (currentTab === "policy") f = f.filter((p) => ["POLICY", "LAW"].includes(mapCat(p)));
    else if (currentTab === "economy") f = f.filter((p) => mapCat(p) === "ECONOMY" || mapCat(p) === "ENERGY");
    if (currentCat !== "ALL") f = f.filter((p) => mapCat(p) === currentCat);
    if (currentAgency) f = f.filter((p) => (p.agency || "").includes(currentAgency));
    if (currentDays !== "all") {
      const ref = latestDate;
      f = f.filter((p) => {
        const d = new Date(p.date);
        return (ref - d) / (1e3 * 60 * 60 * 24) <= Number(currentDays);
      });
    }
    if (currentSearch) {
      const q = currentSearch.toLowerCase();
      f = f.filter(
        (p) =>
          (p.title || "").toLowerCase().includes(q) ||
          (p.content || "").toLowerCase().includes(q) ||
          (p.agency || "").toLowerCase().includes(q) ||
          (p.tags || []).some((t) => t.toLowerCase().includes(q))
      );
    }
    return f;
  }

  function renderCards() {
    const posts = getFiltered();
    updateStats(posts);
    sectionLabel.textContent = `${posts.length} ข่าว`;
    emptyMsg.style.display = posts.length ? "none" : "block";
    cardGrid.innerHTML = posts
      .map((p, i) => {
        const cat = mapCat(p);
        const tags = (p.tags || []).slice(0, 3);
        return `<div class="news-card priority-${p.priority || "B"}" onclick="openModal(${i})"><div class="card-top"><span class="cat-badge cat-${cat}">${p.topic || cat}</span><span class="agency-tag">${p.agency || ""}</span>${p.bd_opportunity ? '<span class="bd-badge">BD</span>' : ""}<span class="date-tag">${p.date || ""}</span></div><div class="card-headline">${p.title || ""}</div><div class="card-summary">${(p.content || "").substring(0, 200)}...</div>${tags.length ? `<div class="card-highlights">${tags.map((t) => `<span class="hl-chip">${t}</span>`).join("")}</div>` : ""}<div class="card-footer"><a class="src-link" href="${p.source_url || "#"}" target="_blank" onclick="event.stopPropagation()">แหล่งข่าว</a></div></div>`;
      })
      .join("");
  }

  window.openModal = function openModal(idx) {
    const posts = getFiltered();
    const p = posts[idx];
    if (!p) return;
    modalBox.innerHTML = `<button class="modal-close" onclick="closeModal()">✕</button><div class="card-top" style="margin-bottom:10px"><span class="cat-badge cat-${mapCat(p)}">${p.topic || ""}</span><span class="agency-tag">${p.agency || ""}</span></div><div class="modal-headline">${p.title || ""}</div><div class="modal-meta">${p.date || ""} · ${p.category_label || ""} · Priority ${p.priority || "B"}</div><div class="modal-body">${p.content || ""}</div>${p.bd_opportunity ? `<div class="modal-section"><h4>โอกาสทางธุรกิจ</h4><p>${p.bd_opportunity}</p></div>` : ""}<a class="modal-link" href="${p.source_url || "#"}" target="_blank">ดูแหล่งข้อมูลต้นฉบับ</a>`;
    modalOverlay.classList.add("open");
    document.body.style.overflow = "hidden";
  };

  window.closeModal = function closeModal() {
    modalOverlay.classList.remove("open");
    document.body.style.overflow = "";
  };

  function renderSpecial(tab) {
    let posts = [];
    if (tab === "proc")
      posts = allPosts.filter(
        (p) => (p.tags || []).some((t) => /จัดซื้อ|tender|e-GP|ประกวดราคา/i.test(t)) || p.bd_opportunity
      );
    else if (tab === "tax") posts = allPosts.filter((p) => (p.tags || []).some((t) => /ภาษี|สรรพากร|tax/i.test(t)));
    else if (tab === "labor")
      posts = allPosts.filter((p) => (p.tags || []).some((t) => /แรงงาน|ประกันสังคม|labor/i.test(t)));
    const c = document.getElementById("specialContent");
    if (!posts.length) {
      c.innerHTML = '<div class="empty-msg">ไม่พบข่าวในหมวดนี้</div>';
      return;
    }
    c.innerHTML = `<div class="card-grid" style="margin-top:16px">${posts
      .map(
        (p) =>
          `<div class="news-card priority-${p.priority || "B"}"><div class="card-top"><span class="cat-badge cat-${mapCat(p)}">${p.topic || ""}</span><span class="agency-tag">${p.agency || ""}</span></div><div class="card-headline">${p.title || ""}</div><div class="card-summary">${(p.content || "").substring(0, 150)}...</div></div>`
      )
      .join("")}</div>`;
  }

  document.querySelectorAll(".tab-btn").forEach((b) => {
    b.addEventListener("click", () => {
      document.querySelectorAll(".tab-btn").forEach((x) => x.classList.remove("active"));
      b.classList.add("active");
      currentTab = b.dataset.tab;
      if (currentTab === "special") {
        mainContent.style.display = "none";
        filterBar.style.display = "none";
        specialPage.classList.add("active");
        renderSpecial("proc");
      } else {
        mainContent.style.display = "";
        filterBar.style.display = "";
        specialPage.classList.remove("active");
        renderCards();
      }
    });
  });

  document.querySelectorAll(".filter-btn").forEach((b) => {
    b.addEventListener("click", () => {
      document.querySelectorAll(".filter-btn").forEach((x) => x.classList.remove("active"));
      b.classList.add("active");
      currentCat = b.dataset.cat;
      renderCards();
    });
  });

  document.getElementById("agencyFilter").addEventListener("change", (e) => {
    currentAgency = e.target.value;
    renderCards();
  });
  document.getElementById("daysFilter").addEventListener("change", (e) => {
    currentDays = e.target.value;
    renderCards();
  });
  document.getElementById("searchInput").addEventListener("input", (e) => {
    currentSearch = e.target.value;
    renderCards();
  });
  modalOverlay.addEventListener("click", (e) => {
    if (e.target === modalOverlay) closeModal();
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeModal();
  });
  document.querySelectorAll(".special-tab-btn").forEach((b) => {
    b.addEventListener("click", () => {
      document.querySelectorAll(".special-tab-btn").forEach((x) => x.classList.remove("active"));
      b.classList.add("active");
      renderSpecial(b.dataset.stab);
    });
  });

  tabNews?.addEventListener("click", () => setHash("news"));
  tabBrain?.addEventListener("click", () => setHash("brain"));
  tabConnect?.addEventListener("click", () => setHash("connect"));
  window.addEventListener("hashchange", () => {
    route();
  });

  window.NewsApp = {
    getPosts: () => allPosts,
  };

  bindConnect();
  loadAllPosts().then(() => {
    bootstrapped = true;
    route();
  });
})();

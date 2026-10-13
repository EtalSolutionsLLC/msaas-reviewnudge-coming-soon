/* Portmason Collections: filesystem-backed browser selection runtime. */
(function (root, factory) {
  "use strict";
  var runtime = factory();
  if (typeof module === "object" && module.exports) module.exports = runtime;
  if (root) root.PortmasonCollectionRuntime = runtime;
}(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  var HIDDEN_STATUSES = { hidden: true, archived: true, retired: true };

  function requireObject(value, label) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("Portmason Collections: " + label + " must be an object");
    }
    return value;
  }

  function zonedDateParts(value, timeZone) {
    if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
      var literal = value.split("-").map(Number);
      var check = new Date(Date.UTC(literal[0], literal[1] - 1, literal[2]));
      if (check.getUTCFullYear() === literal[0]
          && check.getUTCMonth() + 1 === literal[1]
          && check.getUTCDate() === literal[2]) {
        return { year: literal[0], month: literal[1], day: literal[2] };
      }
    }
    var date = value instanceof Date ? value : new Date(value);
    var parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: String(timeZone || "UTC"),
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    }).formatToParts(date);
    function numberPart(type) {
      return Number(parts.find(function (part) { return part.type === type; }).value);
    }
    return { year: numberPart("year"), month: numberPart("month"), day: numberPart("day") };
  }

  function selectionDate(manifest, now) {
    var selection = requireObject(manifest.selection, "manifest selection");
    var parts = zonedDateParts(now || new Date(), selection.timezone || "UTC");
    return [parts.year, String(parts.month).padStart(2, "0"), String(parts.day).padStart(2, "0")].join("-");
  }

  function currentSlot(manifest, now) {
    var selection = requireObject(manifest.selection, "manifest selection");
    var parts = zonedDateParts(now || new Date(), selection.timezone || "UTC");
    var weekday = new Date(Date.UTC(parts.year, parts.month - 1, parts.day)).getUTCDay();
    return weekday || 7;
  }

  function weekOfMonth(manifest, now) {
    var selection = requireObject(manifest.selection, "manifest selection");
    var parts = zonedDateParts(now || new Date(), selection.timezone || "UTC");
    return Math.floor((parts.day - 1) / 7) + 1;
  }

  function displayEligible(item, byId) {
    if (HIDDEN_STATUSES[String(item.status || "").toLowerCase()]) return false;
    var dependencies = Array.isArray(item.displayAfter) ? item.displayAfter : [];
    return dependencies.every(function (reference) {
      var predecessor = byId[Number(reference)];
      return predecessor && predecessor.dateFirstDisplayed != null;
    });
  }

  function visibleCount(manifest, itemCount) {
    var requested = Number(manifest.selection && manifest.selection.visibleItems) || 1;
    return Math.max(1, Math.min(requested, itemCount));
  }

  function selectWeekdayItems(manifest, items, now) {
    var activeSlot = currentSlot(manifest, now);
    var monthWeek = weekOfMonth(manifest, now);
    var byId = Object.create(null);
    items.forEach(function (item) { byId[Number(item.id)] = item; });
    var eligible = items.filter(function (item) { return displayEligible(item, byId); });
    if (!eligible.length) return [];
    var selected = [];
    var seen = Object.create(null);
    var limit = visibleCount(manifest, eligible.length);

    for (var offset = 0; offset < 7 && selected.length < limit; offset += 1) {
      var slot = ((activeSlot - 1 + offset) % 7) + 1;
      var matches = eligible.filter(function (item) { return Number(item.slot) === slot; });
      var batches = [];
      for (var index = 0; index < matches.length; index += 3) batches.push(matches.slice(index, index + 3));
      var batch = batches.length ? batches[(monthWeek - 1) % batches.length] : [];
      batch.forEach(function (item) {
        if (!seen[item.id] && selected.length < limit) {
          selected.push(item);
          seen[item.id] = true;
        }
      });
    }

    eligible.forEach(function (item) {
      if (!seen[item.id] && selected.length < limit) {
        selected.push(item);
        seen[item.id] = true;
      }
    });
    return selected;
  }

  function dateValue(item) {
    var parsed = Date.parse(item.publishDate || item.dateFirstDisplayed || "");
    return Number.isFinite(parsed) ? parsed : -8640000000000000;
  }

  function selectLatestItems(manifest, items) {
    var byId = Object.create(null);
    items.forEach(function (item) { byId[Number(item.id)] = item; });
    var eligible = items.filter(function (item) { return displayEligible(item, byId); });
    return eligible.sort(function (first, second) {
      return dateValue(second) - dateValue(first) || Number(second.id) - Number(first.id);
    }).slice(0, visibleCount(manifest, eligible.length));
  }

  function selectPublicationItems(manifest, items, now) {
    requireObject(manifest, "manifest");
    if (!Array.isArray(items)) throw new Error("Portmason Collections: items must be an array");
    var strategy = String(manifest.selection && manifest.selection.strategy || "latest");
    if (strategy === "weekday-week-of-month") return selectWeekdayItems(manifest, items, now || new Date());
    if (strategy === "latest") return selectLatestItems(manifest, items);
    throw new Error("Portmason Collections: unsupported selection strategy: " + strategy);
  }

  function fetchJson(url, label, fetchImpl) {
    var request = fetchImpl || (typeof fetch === "function" ? fetch.bind(globalThis) : null);
    if (!request) return Promise.reject(new Error("Portmason Collections: fetch is unavailable"));
    return request(url, { cache: "no-store" }).then(function (response) {
      if (!response.ok) throw new Error("Portmason Collections: " + label + " returned HTTP " + response.status);
      return response.json();
    });
  }

  function browserSelectionClock(settings) {
    if (settings.now) return settings.now;
    var location = typeof globalThis.location === "object" ? globalThis.location : null;
    var protocol = String(location && location.protocol || "");
    var hostname = String(location && location.hostname || "").toLowerCase();
    var developmentHost = protocol === "http:" || protocol === "https:"
      ? hostname === "localhost"
        || hostname === "127.0.0.1"
        || hostname === "::1"
        || hostname.endsWith(".localtest.me")
      : false;
    if (!developmentHost) return new Date();
    try {
      var candidate = new URL(location.href).searchParams.get("test_date") || "";
      if (/^\d{4}-\d{2}-\d{2}$/.test(candidate)) {
        var parts = candidate.split("-").map(Number);
        var check = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
        if (check.getUTCFullYear() === parts[0]
            && check.getUTCMonth() + 1 === parts[1]
            && check.getUTCDate() === parts[2]) return candidate;
      }
    } catch (error) {
      // Invalid development URLs use the real clock.
    }
    return new Date();
  }

  function loadCollection(manifestUrl, options) {
    var settings = options || {};
    var clock = browserSelectionClock(settings);
    var absoluteManifestUrl = new URL(manifestUrl, settings.baseUrl || globalThis.location.href);
    return fetchJson(absoluteManifestUrl, "manifest", settings.fetchImpl).then(function (manifest) {
      requireObject(manifest, "manifest");
      var dataFile = String(manifest.dataFile || "").trim();
      if (!dataFile) throw new Error("Portmason Collections: manifest dataFile is required");
      var dataUrl = new URL(dataFile, absoluteManifestUrl);
      return fetchJson(dataUrl, "items", settings.fetchImpl).then(function (items) {
        if (!Array.isArray(items)) throw new Error("Portmason Collections: items must be an array");
        return {
          manifest: manifest,
          items: items,
          selectedItems: manifest.mode === "publication"
            ? selectPublicationItems(manifest, items, clock)
            : items,
          selectionDate: manifest.mode === "publication"
            ? selectionDate(manifest, clock)
            : null,
          manifestUrl: absoluteManifestUrl,
          dataUrl: dataUrl
        };
      });
    });
  }

  return Object.freeze({
    currentSlot: currentSlot,
    browserSelectionClock: browserSelectionClock,
    loadCollection: loadCollection,
    selectPublicationItems: selectPublicationItems,
    selectionDate: selectionDate,
    weekOfMonth: weekOfMonth
  });
}));

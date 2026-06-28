import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";

const SECTION_KEY = "custom_topics_sidebar_expanded";

function normalizeList(value) {
  if (!value) {
    return [];
  }

  if (Array.isArray(value)) {
    return value;
  }

  return String(value)
    .split("|")
    .map((item) => item.trim())
    .filter(Boolean);
}

export default class CustomTopicsSidebar extends Component {
  @service site;
  @service router;
  @service("current-user") currentUser;

  @tracked expanded;
  @tracked refreshToken = 0;
  @tracked currentPath = "";

  constructor() {
    super(...arguments);

    const stored = localStorage.getItem(SECTION_KEY);

    if (stored === null) {
      this.expanded = !settings.custom_topics_sidebar_collapsed_by_default;
    } else {
      this.expanded = stored === "true";
    }

    this.currentPath = this.router.currentURL || window.location.pathname;

    this._routeChanged = () => {
      this.currentPath = this.router.currentURL || window.location.pathname;
      this.refreshToken++;
    };

    this._refresh = () => {
      this.refreshToken++;
    };

    this.router.on?.("routeDidChange", this._routeChanged);

    window.addEventListener("focus", this._refresh);

    // Helps the sidebar re-check category unread/new state if Discourse updates
    // category tracking state without re-rendering this connector.
    this._timer = window.setInterval(this._refresh, 30000);
  }

  willDestroy() {
    super.willDestroy?.();

    this.router.off?.("routeDidChange", this._routeChanged);

    window.removeEventListener("focus", this._refresh);

    if (this._timer) {
      window.clearInterval(this._timer);
    }
  }

  get shouldShow() {
    if (!settings.custom_topics_sidebar_enabled) {
      return false;
    }

    if (!settings.custom_topics_sidebar_show_for_anon && !this.currentUser) {
      return false;
    }

    return this.categoryItems.length || this.customLinkItems.length;
  }

  get title() {
    return settings.custom_topics_sidebar_title || "Topics";
  }

  get sectionId() {
    return "sidebar-section-content-custom-topics";
  }

  get categoryIds() {
    return normalizeList(settings.custom_topics_sidebar_category_ids)
      .flatMap((item) => String(item).split(","))
      .map((item) => parseInt(item.trim(), 10))
      .filter((id) => Number.isInteger(id));
  }

  get categoriesById() {
    const map = new Map();

    for (const category of this.site.categories || []) {
      map.set(Number(category.id), category);
    }

    return map;
  }

  get categoryItems() {
    this.refreshToken;

    return this.categoryIds
      .map((id) => this.categoriesById.get(id))
      .filter(Boolean)
      .map((category) => {
        return {
          type: "category",
          id: category.id,
          title: category.name,
          href: this.categoryHref(category),
          colorStyle: this.categoryColorStyle(category),
          hasUnread: this.categoryHasUnread(category),
          unreadTitle: category.statTitle || "Unread or new topics",
          active: this.isActiveCategory(category),
        };
      });
  }

  get customLinkItems() {
    return normalizeList(settings.custom_topics_sidebar_custom_links)
      .map((item) => {
        const [title, href, icon = "link", visibility = ""] = item
          .split(",")
          .map((part) => part.trim());

        if (!title || !href) {
          return null;
        }

        if (visibility === "staff" && !this.currentUser?.staff) {
          return null;
        }

        return {
          type: "custom",
          title,
          href,
          icon,
          external: /^https?:\/\//.test(href),
          active: this.isActiveHref(href),
        };
      })
      .filter(Boolean);
  }

  get allItems() {
    return [...this.categoryItems, ...this.customLinkItems];
  }

  categoryHref(category) {
    const slug = category.slug || category.name?.toLowerCase().replace(/\s+/g, "-");

    return `/c/${slug}/${category.id}`;
  }

  categoryColorStyle(category) {
    const color =
      category.color ||
      category.get?.("color") ||
      category.parentCategory?.color ||
      "0088CC";

    return htmlSafe(`color: #${color}`);
  }

  categoryHasUnread(category) {
    const values = [
      category.stat,
      category.unread_count,
      category.unread_topics,
      category.unreadTopics,
      category.new_count,
      category.new_topics,
      category.newTopics,
      category.hasUnread,
      category.hasNew,
      category.has_unread,
      category.has_new,
    ];

    return values.some((value) => {
      if (value === true) {
        return true;
      }

      if (typeof value === "number") {
        return value > 0;
      }

      if (typeof value === "string") {
        const clean = value.trim();

        return clean !== "" && clean !== "0" && clean !== "false";
      }

      return false;
    });
  }

  isActiveCategory(category) {
    const href = this.categoryHref(category);
    const path = this.currentPath || window.location.pathname;

    return (
      path === href ||
      path.startsWith(`${href}/`) ||
      path.startsWith(`${href}?`)
    );
  }

  isActiveHref(href) {
    const path = this.currentPath || window.location.pathname;

    return path === href || path.startsWith(`${href}?`);
  }

  iconHref(icon) {
    return htmlSafe(`#${icon}`);
  }

  iconClass(icon) {
    return htmlSafe(
      `fa d-icon d-icon-${icon} svg-icon fa-width-auto svg-string`
    );
  }

  @action
  toggle() {
    this.expanded = !this.expanded;
    localStorage.setItem(SECTION_KEY, String(this.expanded));
  }

  <template>
    {{#if this.shouldShow}}
      <div
        data-section-name="custom-topics"
        class="sidebar-section sidebar-section-wrapper custom-topics-sidebar-section {{if this.expanded 'sidebar-section--expanded'}}"
      >
        <div class="sidebar-section-header-wrapper sidebar-row">
          <button
            class="btn no-text sidebar-section-header sidebar-section-header-collapsable btn-transparent"
            aria-controls={{this.sectionId}}
            aria-expanded={{this.expanded}}
            title="Toggle section"
            type="button"
            {{on "click" this.toggle}}
          >
            <span class="sidebar-section-header-caret">
              {{#if this.expanded}}
                <svg class="fa d-icon d-icon-angle-down svg-icon fa-width-auto svg-string" width="1em" height="1em" aria-hidden="true">
                  <use href="#angle-down"></use>
                </svg>
              {{else}}
                <svg class="fa d-icon d-icon-angle-right svg-icon fa-width-auto svg-string" width="1em" height="1em" aria-hidden="true">
                  <use href="#angle-right"></use>
                </svg>
              {{/if}}
            </span>

            <span class="sidebar-section-header-text">
              {{this.title}}
            </span>
          </button>
        </div>

        {{#if this.expanded}}
          <ul id={{this.sectionId}} class="sidebar-section-content">
            {{#each this.allItems as |item|}}
              <li
                data-list-item-name={{item.title}}
                class="sidebar-section-link-wrapper"
              >
                <a
                  href={{item.href}}
                  rel={{if item.external "noopener noreferrer"}}
                  target={{if item.external "_blank" "_self"}}
                  data-link-name={{item.title}}
                  class="sidebar-section-link sidebar-row {{if item.active 'active'}} {{if item.active 'sidebar-section-link--active'}}"
                >
                  {{#if (eq item.type "category")}}
                    <span
                      style={{item.colorStyle}}
                      class="sidebar-section-link-prefix icon"
                    >
                      <svg class="fa d-icon d-icon-square-full svg-icon fa-width-auto prefix-icon svg-string" width="1em" height="1em" aria-hidden="true">
                        <use href="#square-full"></use>
                      </svg>
                    </span>
                  {{else}}
                    <span class="sidebar-section-link-prefix icon">
                      <svg
                        class={{this.iconClass item.icon}}
                        width="1em"
                        height="1em"
                        aria-hidden="true"
                      >
                        <use href={{this.iconHref item.icon}}></use>
                      </svg>
                    </span>
                  {{/if}}

                  <span class="sidebar-section-link-content-text">
                    {{item.title}}
                  </span>

                  {{#if item.hasUnread}}
                    <span
                      class="sidebar-section-link-suffix icon unread"
                      title={{item.unreadTitle}}
                    >
                      <svg class="fa d-icon d-icon-circle svg-icon fa-width-auto svg-string" width="1em" height="1em" aria-hidden="true">
                        <use href="#circle"></use>
                      </svg>
                    </span>
                  {{/if}}
                </a>
              </li>
            {{/each}}
          </ul>
        {{/if}}
      </div>
    {{/if}}
  </template>
}

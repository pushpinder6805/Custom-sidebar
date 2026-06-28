import { tracked } from "@glimmer/tracking";
import { schedule } from "@ember/runloop";
import { service } from "@ember/service";
import { dasherize } from "@ember/string";
import { apiInitializer } from "discourse/lib/api";
import { getCollapsedSidebarSectionKey } from "discourse/lib/sidebar/helpers";
import Category from "discourse/models/category";
import { settings } from "virtual:theme";

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

function categoryIds() {
  return normalizeList(settings.custom_topics_sidebar_category_ids)
    .flatMap((item) => String(item).split(","))
    .map((item) => Number.parseInt(item.trim(), 10))
    .filter(Number.isInteger);
}

function customLinks() {
  return normalizeList(settings.custom_topics_sidebar_custom_links)
    .map((item, index) => {
      const [text, href, icon = "link", visibility = ""] = item
        .split(",")
        .map((part) => part.trim());

      if (!text || !href) {
        return null;
      }

      // Existing installations may retain the old default `link` icon even
      // after the setting default changes. Upgrade that legacy value at render
      // time without overriding an icon explicitly chosen by an admin.
      const resolvedIcon =
        href === "/top" && icon === "link" ? "arrow-right" : icon;

      return { text, href, icon: resolvedIcon, visibility, index };
    })
    .filter(Boolean);
}

function hasUnreadTopics(category, topicTrackingState, currentUser) {
  try {
    if (currentUser?.unified_new_enabled) {
      return (
        topicTrackingState.countNewAndUnread?.({ categoryId: category.id }) > 0
      );
    }

    if (
      topicTrackingState.countUnread?.({ categoryId: category.id }) > 0 ||
      topicTrackingState.countNew?.({ categoryId: category.id }) > 0
    ) {
      return true;
    }
  } catch {
    // Fall back to the serialized category counts on older Discourse versions.
  }

  return [
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
  ].some((value) => {
    if (value === true || (typeof value === "number" && value > 0)) {
      return true;
    }

    if (typeof value === "string") {
      const normalized = value.trim().toLowerCase();
      return normalized !== "" && normalized !== "0" && normalized !== "false";
    }

    return false;
  });
}

export default apiInitializer((api) => {
  if (!settings.custom_topics_sidebar_enabled) {
    return;
  }

  api.addSidebarSection(
    (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
      class CustomTopicsCategoryLink extends BaseCustomSidebarSectionLink {
        route = "discovery.category";
        currentWhen =
          "discovery.unreadCategory discovery.hotCategory discovery.topCategory discovery.newCategory discovery.latestCategory discovery.category discovery.categoryNone discovery.categoryAll";
        suffixType = "icon";
        suffixCSSClass = "unread";

        constructor({ category, topicTrackingState, currentUser }) {
          super(...arguments);
          this.category = category;
          this.topicTrackingState = topicTrackingState;
          this.currentUser = currentUser;
        }

        get name() {
          return `custom-topics-category-${this.category.id}`;
        }

        get model() {
          return `${Category.slugFor(this.category)}/${this.category.id}`;
        }

        get title() {
          return this.category.descriptionText || this.category.name;
        }

        get text() {
          return this.category.displayName || this.category.name;
        }

        get suffixValue() {
          if (
            hasUnreadTopics(
              this.category,
              this.topicTrackingState,
              this.currentUser,
            )
          ) {
            return "circle";
          }
        }
      }

      class CustomTopicsLink extends BaseCustomSidebarSectionLink {
        suffixType = "icon";
        suffixCSSClass = "custom-link-icon";

        constructor({ link, router }) {
          super(...arguments);
          this.link = link;
          this.router = router;
        }

        get name() {
          return `custom-topics-link-${this.link.index}-${dasherize(
            this.link.text,
          )}`;
        }

        get href() {
          return this.link.href;
        }

        get title() {
          return this.link.text;
        }

        get text() {
          return this.link.text;
        }

        get suffixValue() {
          return this.link.icon;
        }

        get currentWhen() {
          if (/^https?:\/\//i.test(this.link.href)) {
            return false;
          }

          const currentPath = (this.router.currentURL || "").split("?")[0];
          const linkPath = this.link.href.split("?")[0];

          return (
            currentPath === linkPath ||
            (linkPath !== "/" && currentPath.startsWith(`${linkPath}/`))
          );
        }
      }

      return class CustomTopicsSidebarSection extends BaseCustomSidebarSection {
        @service currentUser;
        @service keyValueStore;
        @service router;
        @service site;
        @service topicTrackingState;

        @tracked refreshToken = 0;

        name = "custom-topics";

        willDestroy() {
          if (this.trackingCallbackId !== undefined) {
            this.topicTrackingState.offStateChange?.(this.trackingCallbackId);
          }
        }

        get text() {
          return settings.custom_topics_sidebar_title || "Topics";
        }

        get title() {
          return this.text;
        }

        get collapsedByDefault() {
          return false;
        }

        get displaySection() {
          if (
            !settings.custom_topics_sidebar_show_for_anon &&
            !this.currentUser
          ) {
            return false;
          }

          return this.links.length > 0;
        }

        get links() {
          this.refreshToken;

          this.keyValueStore.setItem(
            getCollapsedSidebarSectionKey(this.name),
            "false",
          );

          if (!this.headerLockScheduled) {
            this.headerLockScheduled = true;
            schedule("afterRender", () => {
              document
                .querySelectorAll(
                  '[data-section-name="custom-topics"] .sidebar-section-header',
                )
                .forEach((header) => {
                  header.setAttribute("tabindex", "-1");
                  header.setAttribute("aria-disabled", "true");
                  header.removeAttribute("title");
                });
            });
          }

          // Discourse assigns the Ember owner after constructing API sections,
          // so services must not be accessed from the constructor.
          if (!this.trackingSubscriptionInitialized) {
            this.trackingSubscriptionInitialized = true;
            this.trackingCallbackId = this.topicTrackingState.onStateChange?.(
              () => this.refreshToken++,
            );
          }

          const categoriesById = new Map(
            (this.site.categories || []).map((category) => [
              Number(category.id),
              category,
            ]),
          );

          const categoryLinks = categoryIds()
            .map((id) => categoriesById.get(id))
            .filter(Boolean)
            .map(
              (category) =>
                new CustomTopicsCategoryLink({
                  category,
                  topicTrackingState: this.topicTrackingState,
                  currentUser: this.currentUser,
                }),
            );

          const configuredLinks = customLinks()
            .filter(
              (link) => link.visibility !== "staff" || this.currentUser?.staff,
            )
            .map(
              (link) =>
                new CustomTopicsLink({
                  link,
                  router: this.router,
                }),
            );

          return [...categoryLinks, ...configuredLinks];
        }
      };
    },
    "main",
  );
});

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'

import type { CaseVariant, ReanalysisAlert } from '@/api/casearchive/types'
import { useCaseArchiveStore } from '@/stores/casearchive'

const caseArchiveStore = useCaseArchiveStore()

/** Whether the "import bookmarks" dialog is shown. */
const showImportDialog = ref(false)
/** Whether the "data versions" dialog is shown. */
const showDataVersionsDialog = ref(false)
/** Which variant's ACMG history is expanded. */
const expandedHistory: Record<string, boolean> = reactive({})
/** Variant currently being re-analysed. */
const busyVariant = ref<string | null>(null)
/** Whether a case-wide re-analysis is running. */
const busyCase = ref(false)

/** Variant id for which history has been requested. */
const loadHistoryFor = async (variant: CaseVariant) => {
  if (!expandedHistory[variant.id]) {
    await caseArchiveStore.loadHistory(variant.id)
  }
  expandedHistory[variant.id] = !expandedHistory[variant.id]
}

/** Follow / unfollow a variant. */
const toggleFollow = async (variant: CaseVariant) => {
  await caseArchiveStore.updateVariant(variant.id, { follow: !variant.follow })
}

/** Re-analyse a single variant. */
const reanalyze = async (variant: CaseVariant) => {
  busyVariant.value = variant.id
  try {
    await caseArchiveStore.reanalyzeVariant(variant.id)
  } finally {
    busyVariant.value = null
  }
}

/** Re-analyse the whole case. */
const reanalyzeAll = async () => {
  busyCase.value = true
  try {
    await caseArchiveStore.reanalyzeCase()
  } finally {
    busyCase.value = false
  }
}

/** Import the user's bookmarks. */
const doImport = async (overwrite: boolean) => {
  showImportDialog.value = false
  await caseArchiveStore.importBookmarks(['seqvar'], overwrite)
}

/** Map an ACMG class string to a chip color. */
const classColor = (acmgClass: string): string => {
  const lowered = acmgClass.toLowerCase()
  if (lowered.includes('pathogenic') && !lowered.includes('likely')) return 'red'
  if (lowered.includes('likely pathogenic')) return 'orange'
  if (lowered.includes('benign') && !lowered.includes('likely')) return 'green'
  if (lowered.includes('likely benign')) return 'lime'
  return 'grey'
}

/** Human-readable date. */
const fmtDate = (iso: string | null): string => (iso ? new Date(iso).toLocaleString() : '–')

/** Unread alerts sorted newest first. */
const unreadAlerts = computed<ReanalysisAlert[]>(() =>
  caseArchiveStore.alerts.filter((alert) => alert.read_at === null)
)

/** Find a variant by id, for alert display. */
const variantLabel = (variantId: string): string => {
  const variant = caseArchiveStore.variants.find((v) => v.id === variantId)
  return variant ? variantLabelOf(variant) : variantId
}

/** Short display label of a variant. */
const variantLabelOf = (variant: CaseVariant): string =>
  variant.label || variant.gene_symbol || variant.obj_id

onMounted(async () => {
  await caseArchiveStore.initialize()
  if (caseArchiveStore.storeState === 'active') {
    await caseArchiveStore.loadDataVersions()
  }
})
</script>

<template>
  <v-card class="mx-auto pa-4 pb-8 mt-3">
    <v-card-title>
      Case archive
      <v-badge
        v-if="caseArchiveStore.nAlertsUnread > 0"
        :content="String(caseArchiveStore.nAlertsUnread)"
        color="warning"
        inline
      />
    </v-card-title>
    <v-card-text>
      <v-alert v-if="caseArchiveStore.message" type="error" density="compact">
        {{ caseArchiveStore.message }}
      </v-alert>

      <template v-if="caseArchiveStore.storeState === 'active'">
        <!-- Summary line -->
        <div class="d-flex flex-wrap ga-3 align-center mb-4">
          <v-chip variant="tonal" prepend-icon="mdi-dna">
            {{ caseArchiveStore.summary?.n_variants ?? caseArchiveStore.variants.length }} variants
          </v-chip>
          <v-chip variant="tonal" prepend-icon="mdi-eye">
            {{ caseArchiveStore.summary?.n_followed ?? '–' }} followed
          </v-chip>
          <v-chip
            v-for="(count, acmgClass) in caseArchiveStore.summary?.by_class ?? {}"
            :key="acmgClass"
            variant="tonal"
            :color="classColor(String(acmgClass))"
          >
            {{ acmgClass }}: {{ count }}
          </v-chip>
          <v-chip
            v-if="caseArchiveStore.nAlertsUnread > 0"
            variant="tonal"
            color="warning"
            prepend-icon="mdi-bell"
          >
            {{ caseArchiveStore.nAlertsUnread }} unread alerts
          </v-chip>
          <v-chip
            v-if="caseArchiveStore.summary?.last_run"
            variant="tonal"
            prepend-icon="mdi-refresh"
          >
            last run: {{ fmtDate(caseArchiveStore.summary.last_run.started_at) }} ({{
              caseArchiveStore.summary.last_run.n_changed
            }}
            changed)
          </v-chip>
          <v-spacer />
          <v-btn
            prepend-icon="mdi-bookmark-multiple-plus"
            variant="tonal"
            rounded="sm"
            @click="showImportDialog = true"
          >
            Import bookmarks
          </v-btn>
          <v-btn
            prepend-icon="mdi-refresh"
            color="primary"
            variant="tonal"
            rounded="sm"
            :loading="busyCase"
            @click="reanalyzeAll"
          >
            Re-analyse case
          </v-btn>
          <v-btn
            prepend-icon="mdi-database"
            variant="text"
            rounded="sm"
            @click="showDataVersionsDialog = true"
          >
            Data versions
          </v-btn>
        </div>

        <!-- Unread alerts -->
        <v-card v-if="unreadAlerts.length" variant="tonal" color="warning" class="mb-4">
          <v-card-title class="text-subtitle-1">Classification changes</v-card-title>
          <v-list density="compact" bg-color="transparent">
            <v-list-item v-for="alert in unreadAlerts" :key="alert.id">
              <template #prepend>
                <v-icon>mdi-alert-circle-outline</v-icon>
              </template>
              <v-list-item-title>
                {{ variantLabel(alert.case_variant) }}: {{ alert.old_class ?? '?' }} →
                <v-chip :color="classColor(alert.new_class)" size="small" variant="flat">
                  {{ alert.new_class }}
                </v-chip>
              </v-list-item-title>
              <v-list-item-subtitle v-if="alert.message">{{ alert.message }}</v-list-item-subtitle>
              <template #append>
                <v-btn
                  size="small"
                  variant="text"
                  prepend-icon="mdi-check"
                  @click="caseArchiveStore.markAlertRead(alert.id)"
                >
                  Mark read
                </v-btn>
              </template>
            </v-list-item>
          </v-list>
        </v-card>

        <!-- Followed variants -->
        <v-table v-if="caseArchiveStore.variants.length" density="compact">
          <thead>
            <tr>
              <th>Variant</th>
              <th>Gene</th>
              <th>Label</th>
              <th>Latest ACMG</th>
              <th>Last analysed</th>
              <th>Followed</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="variant in caseArchiveStore.variants" :key="variant.id">
              <tr>
                <td>
                  <RouterLink :to="{ name: 'seqvar-details', params: { seqvar: variant.obj_id } }">
                    {{ variant.obj_id }}
                  </RouterLink>
                </td>
                <td>{{ variant.gene_symbol ?? '–' }}</td>
                <td>{{ variant.label ?? '–' }}</td>
                <td>
                  <v-chip
                    v-if="variant.latest"
                    :color="classColor(variant.latest.acmg_class)"
                    size="small"
                    variant="tonal"
                  >
                    {{ variant.latest.acmg_class }}
                  </v-chip>
                  <span v-else>–</span>
                </td>
                <td>{{ fmtDate(variant.last_analyzed_at) }}</td>
                <td>
                  <v-switch
                    :model-value="variant.follow"
                    density="compact"
                    hide-details
                    color="primary"
                    @update:model-value="toggleFollow(variant)"
                  />
                </td>
                <td>
                  <v-btn
                    size="small"
                    variant="text"
                    :icon="expandedHistory[variant.id] ? 'mdi-chevron-up' : 'mdi-history'"
                    @click="loadHistoryFor(variant)"
                  />
                  <v-btn
                    size="small"
                    variant="text"
                    icon="mdi-refresh"
                    :loading="busyVariant === variant.id"
                    @click="reanalyze(variant)"
                  />
                  <v-btn
                    size="small"
                    variant="text"
                    icon="mdi-delete"
                    @click="caseArchiveStore.unfollowVariant(variant.id)"
                  />
                </td>
              </tr>
              <tr v-if="expandedHistory[variant.id]">
                <td colspan="7" class="bg-grey-lighten-4">
                  <div class="text-subtitle-2 mb-2">ACMG history</div>
                  <v-timeline v-if="caseArchiveStore.history[variant.id]?.length" density="compact">
                    <v-timeline-item
                      v-for="assessment in caseArchiveStore.history[variant.id]"
                      :key="assessment.id"
                      :dot-color="classColor(assessment.acmg_class)"
                      size="small"
                    >
                      <div>
                        <v-chip :color="classColor(assessment.acmg_class)" size="small">
                          {{ assessment.acmg_class }}
                        </v-chip>
                        <span class="ml-2 text-caption">
                          {{ fmtDate(assessment.created_at) }} · {{ assessment.source }} ·
                          {{ assessment.engine_version }}
                          <v-chip v-if="assessment.is_conflicting" size="x-small" color="orange">
                            conflicting
                          </v-chip>
                        </span>
                      </div>
                    </v-timeline-item>
                  </v-timeline>
                  <div v-else class="text-caption">No classification history yet.</div>
                </td>
              </tr>
            </template>
          </tbody>
        </v-table>
        <div v-else class="text-body-2 text-grey">
          No variants followed yet. Use "Import bookmarks" to add the variants you bookmarked, or
          follow a variant from its detail page.
        </div>
      </template>
      <div v-else-if="caseArchiveStore.storeState === 'loading'" class="text-body-2 text-grey">
        Loading case archive…
      </div>
    </v-card-text>
  </v-card>

  <!-- Import bookmarks dialog -->
  <v-dialog v-model="showImportDialog" max-width="480">
    <v-card>
      <v-card-title>Import bookmarks</v-card-title>
      <v-card-text>
        Import all bookmarked sequence variants of this user into the case archive. Existing
        followed variants are never duplicated; with "overwrite", variants already followed but
        currently unfollowed are re-enabled.
      </v-card-text>
      <v-card-actions>
        <v-spacer />
        <v-btn @click="showImportDialog = false">Cancel</v-btn>
        <v-btn color="primary" @click="doImport(false)">Import</v-btn>
        <v-btn color="secondary" @click="doImport(true)">Import + overwrite</v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>

  <!-- Data versions dialog -->
  <v-dialog v-model="showDataVersionsDialog" max-width="560">
    <v-card>
      <v-card-title>Reference data versions</v-card-title>
      <v-card-text>
        <v-table v-if="caseArchiveStore.dataVersions.length" density="compact">
          <thead>
            <tr>
              <th>Source</th>
              <th>Version</th>
              <th>First seen</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="dataVersion in caseArchiveStore.dataVersions" :key="dataVersion.id">
              <td>{{ dataVersion.source }}</td>
              <td>{{ dataVersion.version }}</td>
              <td>{{ fmtDate(dataVersion.first_seen_at) }}</td>
            </tr>
          </tbody>
        </v-table>
        <div v-else class="text-caption">No data versions recorded yet.</div>
      </v-card-text>
      <v-card-actions>
        <v-spacer />
        <v-btn @click="showDataVersionsDialog = false">Close</v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

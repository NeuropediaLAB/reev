/**
 * Store for the case archive: followed variants, ACMG history and alerts.
 */
import { StoreState } from '@bihealth/reev-frontend-lib/stores/types'
import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { CaseArchiveClient } from '@/api/casearchive/api'
import type {
  AcmgAssessment,
  CaseArchiveSummary,
  CaseVariant,
  CaseVariantCreate,
  CaseVariantUpdate,
  DataVersion,
  FailureInfo,
  ReanalysisAlert,
  ReanalysisRun
} from '@/api/casearchive/types'
import { MITT } from '@/lib/utils'
import { Events as UserStoreEvents, useUserStore } from '@/stores/user'

export const useCaseArchiveStore = defineStore('caseArchive', () => {
  /** The current store state. */
  const storeState = ref<StoreState>(StoreState.Initial)
  /** The last error message, if any. */
  const message = ref<string | null>(null)

  /** Currently followed variants of the case. */
  const variants = ref<CaseVariant[]>([])
  /** Summary counters for the current case. */
  const summary = ref<CaseArchiveSummary | null>(null)
  /** Alerts of the current case (all, newest first). */
  const alerts = ref<ReanalysisAlert[]>([])
  /** Number of unread alerts. */
  const nAlertsUnread = computed(() => alerts.value.filter((a) => a.read_at === null).length)
  /** Reference data versions. */
  const dataVersions = ref<DataVersion[]>([])
  /** ACMG history cache, keyed by variant id. */
  const history = ref<Record<string, AcmgAssessment[]>>({})
  /** The last re-analysis run launched from this session. */
  const lastRun = ref<ReanalysisRun | null>(null)

  /** API client instance. */
  const client = new CaseArchiveClient()

  /** Clear all data from the store. */
  const clearData = () => {
    variants.value = []
    summary.value = null
    alerts.value = []
    dataVersions.value = []
    history.value = {}
    lastRun.value = null
    message.value = null
    storeState.value = StoreState.Initial
  }

  /** Resolve the current case id from the case info store; null when unavailable. */
  const currentCaseId = async (): Promise<string | null> => {
    const { useCaseInfoStore } = await import('@/stores/caseInfo')
    const caseInfoStore = useCaseInfoStore()
    await caseInfoStore.initialize()
    return caseInfoStore.caseInfo.id ?? null
  }

  /** Handle a failed response: set message and return null. */
  const handleFailure = (failure: FailureInfo | undefined): null => {
    message.value = failure?.detail ?? 'Unknown error'
    return null
  }

  /** Load the followed variants of the current case. */
  const loadVariants = async () => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      storeState.value = StoreState.Error
      message.value = 'No case information available.'
      return
    }
    const response = await client.fetchVariants(caseId)
    if (response.ok && Array.isArray(response.data)) {
      variants.value = response.data
      storeState.value = StoreState.Active
    } else {
      handleFailure(response.data as FailureInfo)
      storeState.value = StoreState.Error
    }
  }

  /** Load the summary counters of the current case. */
  const loadSummary = async () => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return
    }
    const response = await client.fetchSummary(caseId)
    if (response.ok) {
      summary.value = response.data as CaseArchiveSummary
    }
  }

  /** Load the alerts of the current case. */
  const loadAlerts = async () => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return
    }
    const response = await client.fetchAlerts(caseId)
    if (response.ok && Array.isArray(response.data)) {
      alerts.value = response.data
    }
  }

  /** Load everything needed for the case archive view. */
  const initialize = async (force: boolean = false) => {
    if (storeState.value === StoreState.Active && !force) {
      return
    }
    const userStore = useUserStore()
    await userStore.initialize()
    if (!userStore.currentUser) {
      storeState.value = StoreState.Initial
      return
    }
    MITT.on(UserStoreEvents.Logout, () => clearData())
    storeState.value = StoreState.Loading
    await Promise.all([loadVariants(), loadSummary(), loadAlerts()])
    if ((storeState.value as StoreState) !== StoreState.Error) {
      storeState.value = StoreState.Active
    }
  }

  /** Follow a variant within the current case. */
  const followVariant = async (payload: CaseVariantCreate): Promise<CaseVariant | null> => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return null
    }
    const response = await client.createVariant(caseId, payload)
    if (response.ok) {
      await loadVariants()
      await loadSummary()
      return response.data as CaseVariant
    }
    return handleFailure(response.data as FailureInfo)
  }

  /** Update a followed variant (label, notes, follow flag, ...). */
  const updateVariant = async (
    variantId: string,
    payload: CaseVariantUpdate
  ): Promise<CaseVariant | null> => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return null
    }
    const response = await client.updateVariant(caseId, variantId, payload)
    if (response.ok) {
      await loadVariants()
      await loadSummary()
      return response.data as CaseVariant
    }
    return handleFailure(response.data as FailureInfo)
  }

  /** Stop following a variant (removes it and its ACMG history). */
  const unfollowVariant = async (variantId: string): Promise<boolean> => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return false
    }
    const response = await client.deleteVariant(caseId, variantId)
    if (response.ok) {
      await loadVariants()
      await loadSummary()
      return true
    }
    handleFailure(response.data as FailureInfo)
    return false
  }

  /** Import the current user's bookmarks into the case. */
  const importBookmarks = async (
    objTypes: string[] = ['seqvar'],
    overwrite: boolean = false
  ): Promise<number> => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return 0
    }
    const response = await client.importBookmarks(caseId, objTypes, overwrite)
    if (response.ok && Array.isArray(response.data)) {
      await loadVariants()
      await loadSummary()
      return response.data.length
    }
    handleFailure(response.data as FailureInfo)
    return 0
  }

  /** Load (and cache) the ACMG history of a variant. */
  const loadHistory = async (variantId: string): Promise<AcmgAssessment[]> => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return []
    }
    const response = await client.fetchHistory(caseId, variantId)
    if (response.ok && Array.isArray(response.data)) {
      history.value = { ...history.value, [variantId]: response.data }
      return response.data
    }
    handleFailure(response.data as FailureInfo)
    return []
  }

  /** Re-run the ACMG classification of one variant right now. */
  const reanalyzeVariant = async (variantId: string): Promise<AcmgAssessment | null> => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return null
    }
    const response = await client.reanalyzeVariant(caseId, variantId)
    if (response.ok) {
      await Promise.all([loadVariants(), loadSummary(), loadHistory(variantId), loadAlerts()])
      return response.data as AcmgAssessment
    }
    return handleFailure(response.data as FailureInfo)
  }

  /** Re-run the ACMG classification of every followed variant of the case. */
  const reanalyzeCase = async (): Promise<ReanalysisRun | null> => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return null
    }
    const response = await client.reanalyzeCase(caseId)
    if (response.ok) {
      lastRun.value = response.data as ReanalysisRun
      await Promise.all([loadVariants(), loadSummary(), loadAlerts()])
      return lastRun.value
    }
    return handleFailure(response.data as FailureInfo)
  }

  /** Mark an alert as read. */
  const markAlertRead = async (alertId: string): Promise<boolean> => {
    const caseId = await currentCaseId()
    if (caseId === null) {
      return false
    }
    const response = await client.markAlertRead(caseId, alertId)
    if (response.ok) {
      await Promise.all([loadAlerts(), loadSummary()])
      return true
    }
    handleFailure(response.data as FailureInfo)
    return false
  }

  /** Load the reference data versions. */
  const loadDataVersions = async () => {
    const response = await client.fetchDataVersions()
    if (response.ok && Array.isArray(response.data)) {
      dataVersions.value = response.data
    }
  }

  return {
    // data
    storeState,
    message,
    variants,
    summary,
    alerts,
    nAlertsUnread,
    dataVersions,
    history,
    lastRun,
    // functions
    clearData,
    initialize,
    loadVariants,
    loadSummary,
    loadAlerts,
    loadHistory,
    followVariant,
    updateVariant,
    unfollowVariant,
    importBookmarks,
    reanalyzeVariant,
    reanalyzeCase,
    markAlertRead,
    loadDataVersions
  }
})

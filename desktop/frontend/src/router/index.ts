import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      component: () => import('@/layouts/MainLayout.vue'),
      children: [
        { path: '', name: 'library', component: () => import('@/views/LibraryView.vue'), meta: { title: '书架' } },
        { path: 'books/:bookId', name: 'book-detail', component: () => import('@/views/BookDetailView.vue'), meta: { title: '书籍' } },
        { path: 'search', name: 'search', component: () => import('@/views/SearchView.vue'), meta: { title: '知识检索' } },
        { path: 'entities', name: 'entities', component: () => import('@/views/EntitiesView.vue'), meta: { title: '人物知识库' } },
        { path: 'graph', name: 'graph', component: () => import('@/views/GraphView.vue'), meta: { title: '人物关系图谱' } },
        { path: 'timeline', name: 'timeline', component: () => import('@/views/TimelineView.vue'), meta: { title: '历史时间线' } },
        { path: 'notes', name: 'notes', component: () => import('@/views/NotesView.vue'), meta: { title: '批注与书签' } },
        { path: 'tasks', name: 'tasks', component: () => import('@/views/TasksView.vue'), meta: { title: '任务中心' } },
        { path: 'settings', name: 'settings', component: () => import('@/views/SettingsView.vue'), meta: { title: '设置' } },
      ],
    },
    {
      path: '/read/:bookId/:chapterId',
      name: 'reader',
      component: () => import('@/views/ReaderView.vue'),
      meta: { title: '阅读', fullscreen: true },
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
  scrollBehavior(to, _from, savedPosition) {
    if (savedPosition) return savedPosition
    if (to.hash) return { el: to.hash, behavior: 'smooth' }
    return { top: 0 }
  },
})

router.afterEach((to) => {
  document.title = to.meta.title ? `${to.meta.title} · 古文阅读器` : '古文阅读器'
})

export default router

import { BrowserRouter as Router, Routes, Route } from "react-router-dom";
import {
  App,
  ViewChat,
  General,
  KnowledgeBase,
  Model,
  Behavior,
  Audio,
  Chats,
  DevMode,
  Onboarding,
} from "@/pages";
import { DashboardLayout } from "@/layouts";

export default function AppRoutes() {
  return (
    <Router>
      <Routes>
        <Route path="/" element={<App />} />
        <Route path="/onboarding" element={<Onboarding />} />
        <Route element={<DashboardLayout />}>
          <Route path="/chats" element={<Chats />} />
          <Route path="/chats/view/:conversationId" element={<ViewChat />} />
          <Route path="/general" element={<General />} />
          <Route path="/knowledge-base" element={<KnowledgeBase />} />
          <Route path="/model" element={<Model />} />
          <Route path="/behavior" element={<Behavior />} />
          <Route path="/audio" element={<Audio />} />
          <Route path="/dev-mode" element={<DevMode />} />
        </Route>
      </Routes>
    </Router>
  );
}

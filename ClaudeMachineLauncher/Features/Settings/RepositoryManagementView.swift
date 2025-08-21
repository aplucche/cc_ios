import SwiftUI

struct RepositoryManagementView: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @State private var showingAddRepository = false
    @State private var editingRepository: GitRepository?
    
    var body: some View {
        List {
            ForEach(settings.repositories) { repository in
                RepositoryRowView(repository: repository) {
                    editingRepository = repository
                }
            }
            .onDelete(perform: deleteRepositories)
        }
        .navigationTitle("Repositories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") {
                    showingAddRepository = true
                }
            }
        }
        .sheet(isPresented: $showingAddRepository) {
            AddRepositoryView()
        }
        .sheet(item: $editingRepository) { repository in
            EditRepositoryView(repository: repository)
        }
    }
    
    private func deleteRepositories(offsets: IndexSet) {
        for index in offsets {
            let repository = settings.repositories[index]
            settings.deleteRepository(repository)
        }
    }
}

struct RepositoryRowView: View {
    let repository: GitRepository
    let onEdit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(repository.displayName)
                    .font(.headline)
                Spacer()
                Button("Edit") {
                    onEdit()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            
            Text(repository.url)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack {
                Text("Branch: \(repository.branch)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(repository.isValidURL ? .green : .orange)
                        .frame(width: 6, height: 6)
                    Text(repository.isValidURL ? "Valid" : "Check URL")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct AddRepositoryView: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var url = ""
    @State private var branch = "main"
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Repository Details"), 
                        footer: Text("Name is optional - URL will be used if name is empty")) {
                    TextField("Repository Name (optional)", text: $name)
                    TextField("Repository URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Default Branch", text: $branch)
                        .textInputAutocapitalization(.never)
                }
                
                if !url.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: isValidURL ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isValidURL ? .green : .orange)
                            Text(isValidURL ? "Valid repository URL" : "Please check the URL format")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let repository = GitRepository(name: name, url: url, branch: branch)
                        settings.addRepository(repository)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
    
    private var isValidURL: Bool {
        let repository = GitRepository(name: name, url: url, branch: branch)
        return repository.isValidURL
    }
    
    private var canSave: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidURL
    }
}

struct EditRepositoryView: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    
    let repository: GitRepository
    @State private var name: String
    @State private var url: String
    @State private var branch: String
    
    init(repository: GitRepository) {
        self.repository = repository
        self._name = State(initialValue: repository.name)
        self._url = State(initialValue: repository.url)
        self._branch = State(initialValue: repository.branch)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Repository Details"), 
                        footer: Text("Name is optional - URL will be used if name is empty")) {
                    TextField("Repository Name (optional)", text: $name)
                    TextField("Repository URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Default Branch", text: $branch)
                        .textInputAutocapitalization(.never)
                }
                
                if !url.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: isValidURL ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isValidURL ? .green : .orange)
                            Text(isValidURL ? "Valid repository URL" : "Please check the URL format")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Edit Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updatedRepository = repository
                        updatedRepository.name = name
                        updatedRepository.url = url
                        updatedRepository.branch = branch
                        settings.updateRepository(updatedRepository)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
    
    private var isValidURL: Bool {
        let testRepository = GitRepository(name: name, url: url, branch: branch)
        return testRepository.isValidURL
    }
    
    private var canSave: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidURL
    }
}

#Preview {
    RepositoryManagementView()
        .environmentObject(SettingsViewModel.shared)
}
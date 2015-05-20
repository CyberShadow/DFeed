-- Table `Groups`
CREATE TABLE [Groups] (
[Group] VARCHAR(50)  NULL,
[ArtNum] INTEGER  NULL,
[ID] VARCHAR(50)  NULL
, Time INTEGER);

-- Table `Posts`
CREATE TABLE [Posts] (
[ID] VARCHAR(50)  NULL,
[Message] TEXT  NULL,
[Author] VARCHAR(255)  NULL,
[Subject] VARCHAR(255)  NULL,
[Time] INTEGER  NULL,
[ParentID] VARCHAR(50)  NULL,
[ThreadID] VARCHAR(50)  NULL
);

-- Table `Threads`
CREATE TABLE [Threads] (
[Group] VARCHAR(50)  NULL,
[ID] VARCHAR(50)  NULL,
[LastUpdated] INTEGER  NULL
, LastPost VARCHAR(50));

-- Index `PostThreadID` on table `Posts`
CREATE INDEX [PostThreadID] ON [Posts](
[ThreadID]  ASC
);

-- Index `ThreadGroup` on table `Threads`
CREATE INDEX [ThreadGroup] ON [Threads] ( [Group] );

-- Index `GroupTime` on table `Groups`
CREATE INDEX GroupTime ON Groups (`Group`, Time DESC);

-- Index `ThreadOrder` on table `Threads`
CREATE INDEX ThreadOrder ON Threads ([Group], [LastUpdated] DESC);

-- Index `GroupID` on table `Groups`
CREATE UNIQUE INDEX [GroupID] ON [Groups](
[Group]  ASC,
[ID]  ASC
);

-- Index `PostID` on table `Posts`
CREATE UNIQUE INDEX [PostID] ON "Posts"(
[ID]  ASC
);

-- Index `ThreadID` on table `Threads`
CREATE INDEX "ThreadID" ON "Threads" ( ID );

-- Index `PostParentID` on table `Posts`
CREATE INDEX PostParentID ON Posts ( ParentID );

-- Table `Users`
CREATE TABLE [Users] ( [Username] VARCHAR(50), [Password] VARCHAR(50), [Session] VARCHAR(50) , [Level] INTEGER NOT NULL DEFAULT 0);

-- Index `UserName` on table `Users`
CREATE UNIQUE INDEX [UserName] ON [Users] ( [Username] );

-- Table `UserSettings`
CREATE TABLE [UserSettings] ( [User] VARCHAR(50), [Name] VARCHAR(50), [Value] TEXT );

-- Index `UserSetting` on table `UserSettings`
CREATE UNIQUE INDEX [UserSetting] on [UserSettings] ( [User], [Name] );

-- Index `GroupArtNum` on table `Groups`
CREATE INDEX [GroupArtNum] ON [Groups] ( [Group], [ArtNum] );

-- Index `PostTime` on table `Posts`
CREATE INDEX [PostTime] ON [Posts] ( [Time] DESC );

-- Table `Drafts`
CREATE TABLE [Drafts] ([UserID] VARCHAR(20) NOT NULL, [ID] VARCHAR(20) NOT NULL, [ClientVars] TEXT NULL, [ServerVars] TEXT NULL, [Time] INTEGER NOT NULL);

-- Index `DraftID` on table `Drafts`
CREATE INDEX [DraftID] ON [Drafts] ([ID]);

-- Index `DraftUserID` on table `Drafts`
CREATE INDEX [DraftUserID] ON [Drafts] ([UserID]);

